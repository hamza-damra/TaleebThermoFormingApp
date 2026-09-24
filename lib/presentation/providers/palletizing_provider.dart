import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/plan_item_close_request_strings.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/services/palletizing_event.dart';
import '../../core/services/refresh_coordinator.dart';
import '../../core/services/sse_client.dart';
import '../../core/services/takeover_notification_service.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../../domain/entities/bootstrap_response.dart';
import '../../domain/entities/falet_response.dart';
import '../../domain/entities/first_pallet_context.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/pallet_label.dart';
import '../../domain/entities/palletizer_session.dart';
import '../../domain/entities/palletizing_line.dart';
import '../../domain/entities/palletizer_session_state.dart';
import '../../domain/entities/plan_item_close_request.dart';
import '../../domain/entities/session_production_detail.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/session_table_row.dart';
import '../../domain/entities/takeover_request.dart';
import '../../domain/repositories/palletizing_repository.dart';

enum PalletizingState { idle, loading, loaded, error }

/// Per-line UI state. Computed from the cached BootstrapLineState plus the
/// palletizer session, in this priority order:
///   1. pendingHandover* (lineUiMode == PENDING_HANDOVER_*) — a dedicated
///      flow; the line is transiently unauthorized by design, so handover
///      must win even over "no operator".
///   2. waitingForThermoforming (no active operator — authorized == false OR
///      authorizedOperator == null). Checked BEFORE `blocked` because the
///      backend stamps a `blockedReason` (e.g. LINE_NOT_AUTHORIZED) on a
///      no-operator line; without this ordering it routed to `blocked`,
///      which has no overlay, and the blocking waiting modal never showed.
///   3. blocked    (blockedReason != null, operator still present)
///   4. needsPalletizerAuth (authorized && operator && no active session)
///   5. active     (authorized && operator && active session)
enum LineUiState {
  blocked,
  pendingHandoverIncoming,
  pendingHandoverReview,
  waitingForThermoforming,
  needsPalletizerAuth,
  active,
}

/// Adaptive polling cadence buckets, fastest first. The [RefreshCoordinator]
/// reads [PalletizingProvider.nextPollInterval] after every poll and on every
/// SSE state change, and reschedules a single one-shot timer — there is no
/// fixed `Timer.periodic`.
///
/// REST stays the source of truth: SSE is only a refresh trigger and the
/// cadence only decides *how often* the app re-fetches `/state` as a safety
/// net, never what it renders.
enum PollCadence {
  /// Handover / takeover / blocked / waiting-for-operator on any line — an
  /// active transition the app must converge on fast, even with SSE connected.
  urgent(Duration(seconds: 6)),

  /// The last poll round failed outright (network/timeout) — back off a little
  /// from [urgent] but still recover quickly.
  retry(Duration(seconds: 8)),

  /// SSE is disconnected / reconnecting — REST polling is the only refresh
  /// channel, so poll on a brisk fallback cadence.
  fallback(Duration(seconds: 12)),

  /// SSE is connected and a plan-item close request is active on a rendered
  /// line — the handoff's 20–30 s fallback, so a missed cancel / confirm
  /// frame never leaves a stale dialog or banner for a full safety interval.
  closeRequestPending(Duration(seconds: 20)),

  /// SSE is connected and nothing needs attention — a slow safety net behind
  /// the event stream. At least this often the tick re-fetches bootstrap, so
  /// a missed line enable / disable frame is recovered
  /// ([PalletizingProvider.onPollTick]).
  safety(Duration(seconds: 50));

  const PollCadence(this.interval);
  final Duration interval;
}

/// A rendered line appeared in, or disappeared from, a bootstrap refresh.
enum LineAvailabilityChange { added, removed }

/// One-shot UI notice produced when a bootstrap refresh adds or removes a
/// rendered line (admin enabled / disabled it). The screen drains these via
/// [PalletizingProvider.takeLineNotices] and shows a snackbar or the
/// "تم إيقاف الخط" dialog. Never emitted for the first applied bootstrap.
class LineAvailabilityNotice {
  final LineAvailabilityChange change;
  final int lineId;

  /// Resolved label captured when the notice was produced — for a removed
  /// line its state is already pruned.
  final String label;

  /// `true` when a removed line was the selected line at removal time.
  final bool wasSelected;

  const LineAvailabilityNotice({
    required this.change,
    required this.lineId,
    required this.label,
    this.wasSelected = false,
  });
}

/// Why a plan-item close request left the screen — picks the one-shot notice.
enum CloseRequestNoticeKind {
  /// The item was closed and the next item is current.
  confirmed,

  /// The operator cancelled the request.
  cancelled,

  /// The request is no longer valid (invalidated, stale, or gone for a
  /// reason the app cannot tell).
  noLongerValid,
}

/// One-shot notice produced when an active close request disappears. The
/// screen drains these via [PalletizingProvider.takeCloseRequestNotices].
class CloseRequestNotice {
  final int lineId;
  final CloseRequestNoticeKind kind;

  const CloseRequestNotice({required this.lineId, required this.kind});
}

/// Result of a palletizer decision call.
enum CloseDecisionOutcome {
  /// The backend applied the decision (or had already applied it).
  applied,

  /// The request is no longer active (cancelled, invalidated, confirmed
  /// elsewhere, or unknown on this line) — it was removed from the screen.
  requestGone,

  /// The decision failed and the request is still pending; an inline error
  /// is available from [PalletizingProvider.getCloseRequestDecisionError].
  failed,

  /// The palletizer session is missing or ended — the line dropped back to
  /// the PIN screen.
  sessionLost,

  /// Nothing was sent: a decision is already in flight for the line, or the
  /// request on screen is no longer the line's active request.
  ignored,
}

class PalletizingProvider extends ChangeNotifier {
  final PalletizingRepository _repository;
  final AuthLocalStorage _authStorage;
  final TakeoverNotificationService _notifications;

  /// Injectable clock for the bootstrap safety cadence (tests).
  final DateTime Function() _clock;

  /// Owns the poll timer + SSE bridge. `null` in unit tests that construct the
  /// provider without an [SseClient] — the provider then behaves as a pure
  /// REST poller (plus the session-endpoint gate).
  RefreshCoordinator? _coordinator;
  StreamSubscription<SseConnectionState>? _sseStateSub;

  /// Wait before the single automatic retry of a close-request decision that
  /// hit a transient failure (handoff §17). Injectable for tests.
  final Duration _closeDecisionRetryDelay;

  PalletizingProvider(
    this._repository,
    this._authStorage,
    this._notifications, {
    SseClient? sseClient,
    DateTime Function()? clock,
    Duration closeDecisionRetryDelay = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now,
       _closeDecisionRetryDelay = closeDecisionRetryDelay {
    if (sseClient != null) {
      _coordinator = RefreshCoordinator(
        sseClient: sseClient,
        onPoll: onPollTick,
        onEvents: refreshFromSseEvents,
        onFullRefresh: refreshBootstrap,
        nextInterval: () => nextPollInterval,
      );
      // The provider owns the connection-state subscription so `_sseState`
      // (a cadence input) is always updated before the coordinator
      // reschedules the poll timer.
      _sseStateSub = sseClient.connectionState.listen(
        onSseConnectionStateChanged,
      );
    }
  }

  // ── Global state ──
  PalletizingState _state = PalletizingState.idle;
  String? _errorMessage;

  /// `true` while the most recent `loadBootstrap` failed specifically because
  /// the backend rejected the device key (HTTP 401 / 403 on a
  /// `/palletizing-line/*` path → [ApiException.deviceKeyInvalid]). Drives the
  /// dedicated device-key recovery screen (a button to Device Settings) so the
  /// UI never re-uses the generic "بيانات الدخول غير صحيحة" message — which is
  /// reserved for actual PIN / credential failures.
  bool _deviceKeyInvalid = false;

  // ── Reference data ──
  List<ProductType> _productTypes = [];
  Map<int, ProductType> _productTypesById = const {};

  // ── Rendered lines ──
  /// Backend `lineId`s from the last successful bootstrap, in **server
  /// order**. The only source for tabs, panes, polling, takeover dialogs,
  /// announcement lineIds and the "switch line" target. A line absent from
  /// bootstrap is inactive — it is pruned from every per-line map below.
  List<int> _renderedLineIds = const [];

  /// Selected line (tabs mode). Always a rendered id, or `null` when no line
  /// is rendered.
  int? _selectedLineId;

  /// `lineId → lineNumber` for every line seen this process. Deliberately NOT
  /// pruned: a reprint of a pallet from a line that has since been disabled
  /// still prints the same side-band letter.
  final Map<int, int> _lastKnownLineNumbers = {};

  /// `true` once any bootstrap has been applied — line add/remove notices are
  /// only produced after that.
  bool _hasAppliedBootstrap = false;
  final List<LineAvailabilityNotice> _lineNotices = [];

  // ── Bootstrap refresh bookkeeping ──
  Future<void>? _bootstrapInFlight;
  bool _bootstrapRerunRequested = false;
  DateTime? _lastBootstrapAt;

  // ── Per-line state (keyed by backend lineId — never lineNumber) ──
  final Map<int, BootstrapLineState> _lineStates = {};
  final Map<int, PalletizerSessionState> _palletizerSessions = {};
  final Map<int, List<SessionTableRow>> _sessionTables = {};
  final Map<int, ProductType?> _planItemProducts = {};
  final Map<int, PalletCreateResponse?> _lastPalletResponses = {};
  final Map<int, String?> _blockedReasons = {};
  final Map<int, bool> _lineCreating = {};
  final Map<int, String?> _lineErrors = {};
  final Map<int, String?> _lineUiModes = {};
  final Map<int, FaletResponse?> _faletItems = {};
  final Map<int, bool> _faletItemsLoading = {};
  final Map<int, bool> _hasOpenFalet = {};
  final Map<int, int> _openFaletCount = {};
  final Map<int, bool> _firstPalletContextLoading = {};

  // ── Line Takeover Request (V75) — passive observer ──
  // Current takeover per line (null = none). `_lineBlockedFlag` mirrors the
  // backend `blocked` boolean. The id-keyed sets de-dupe the alert/dialog so
  // sound + vibration + dialog fire exactly once per request id.
  final Map<int, TakeoverRequest?> _takeovers = {};
  final Map<int, bool> _lineBlockedFlag = {};
  final Set<String> _alertedTakeoverIds = {};
  final Set<String> _acknowledgedTakeoverIds = {};
  final Set<int> _pendingDialogLines = {};

  // ── Plan-item close handshake (V190) ──
  // Only ACTIVE requests are kept, and only for lines with a palletizer
  // session (the read is token-gated). The map changes only from REST
  // responses — the pending read and the two decisions — never from an SSE
  // frame. See docs: PALLETIZING_PLAN_ITEM_CLOSE_CONFIRMATION.md.
  final Map<int, PlanItemCloseRequest> _closeRequests = {};

  /// Lines with a decision call in flight — disables both dialog buttons and
  /// the banner action, and drops a second tap before it reaches the network.
  final Set<int> _closeDecisionInFlight = {};

  /// Inline message of the last failed decision whose request is still
  /// pending (paused line, conflict, network). Cleared by the next attempt
  /// and whenever the request changes.
  final Map<int, String> _closeDecisionErrors = {};

  /// Per-line counter bumped by every pending read and every applied
  /// decision; a read that was overtaken is dropped, so a slow read can never
  /// resurrect a request a decision just moved on.
  final Map<int, int> _closeRequestSeq = {};

  /// Single-flight pending reads, plus a trailing re-read flag for triggers
  /// that arrive while one is in flight.
  final Map<int, Future<void>> _closeRequestFetches = {};
  final Set<int> _closeRequestRefetchRequested = {};

  /// Lines whose next session refresh must re-read the request regardless of
  /// the poll throttle (bootstrap, resume, reconnect, SSE nudge).
  final Set<int> _closeRequestForced = {};
  final Map<int, DateTime> _closeRequestFetchedAt = {};

  /// Last terminal `PLAN_ITEM_CLOSE_*` SSE reason per line. A wording hint
  /// for the notice shown when the REST read confirms the request is gone —
  /// never a source of state.
  final Map<int, String> _closeRequestSseHint = {};
  final List<CloseRequestNotice> _closeRequestNotices = [];

  /// Minimum age of the last pending read before a routine poll re-reads it.
  static const Duration closeRequestPollInterval = Duration(seconds: 20);

  // ── Adaptive polling ──
  /// `true` when the most recent [pollLineMonitoring] round failed for every
  /// line (network/timeout). Drives the [PollCadence.retry] back-off.
  bool _lastPollFailed = false;

  /// Issue-order generation shared by every line-state read — `/state` and
  /// bootstrap alike. Taken when the request is **sent**.
  int _lineStateRequestGen = 0;

  /// Per line, the generation of the request whose response is currently
  /// applied. A response is applied only when its request was sent after that
  /// one, so a slow response can never overwrite a newer snapshot, whichever
  /// order the responses land in — including a bootstrap sent *before* a
  /// pallet mutation landing after the `/state` read the mutation's SSE frame
  /// triggered. See the SSE handoff §6 (out-of-order REST responses).
  final Map<int, int> _lineStateAppliedGen = {};

  /// Per-line counter bumped whenever an applied line state changes the shift
  /// summary rows. Surfaces that show a different view of the same session
  /// (the production-detail dialog) watch it to re-read the backend.
  final Map<int, int> _sessionDataRevision = {};

  /// Latest device-level SSE connection state. Drives the cadence split
  /// between [PollCadence.safety] (connected) and [PollCadence.fallback].
  SseConnectionState _sseState = SseConnectionState.disconnected;

  // ── Palletizer-session gate ──
  /// Per-line cache (keyed by backend lineId) of whether the app has any local
  /// signal that a palletizer session may exist — a stored session token. When
  /// `false`, `/palletizer-session/current` is NEVER called, which is what
  /// stops the `PALLETIZER_SESSION_REQUIRED` log spam. Primed from secure
  /// storage on bootstrap; set `true` on successful auth, `false` on drop.
  final Map<int, bool> _maybeHasPalletizerSession = {};

  // ── Global getters ──
  PalletizingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == PalletizingState.loading;

  /// `true` when bootstrap failed because the backend rejected this device's
  /// `X-Device-Key`. The screen renders a dedicated recovery surface (Open
  /// Device Settings) instead of the generic error/retry block.
  bool get isDeviceKeyInvalid => _deviceKeyInvalid;
  List<ProductType> get productTypes => _productTypes;

  /// Catalog entry for [productTypeId] from the last bootstrap, or `null`.
  ProductType? productTypeById(int? productTypeId) =>
      productTypeId == null ? null : _productTypesById[productTypeId];

  /// The label to show for a product row from any backend DTO — the catalog's
  /// structured `productName` for [productTypeId], else [backendName] reduced
  /// to its product name. See [ProductType.resolveDisplayName].
  String productDisplayName({
    required int? productTypeId,
    required String? backendName,
  }) => ProductType.resolveDisplayName(
    productType: productTypeById(productTypeId),
    backendName: backendName,
  );

  /// Rendered lines in server order, built from the **latest** state of each
  /// line so a rename shows up on the next `/state` or bootstrap.
  List<PalletizingLine> get renderedLines => [
    for (final id in _renderedLineIds)
      PalletizingLine.fromState(_lineStates[id]!),
  ];

  List<int> get renderedLineIds => List.unmodifiable(_renderedLineIds);

  bool isLineRendered(int lineId) => _renderedLineIds.contains(lineId);

  PalletizingLine? getLine(int lineId) {
    final s = _lineStates[lineId];
    return s == null ? null : PalletizingLine.fromState(s);
  }

  /// Resolved label for [lineId], or a generic 'الخط' when unknown.
  String lineLabel(int lineId) => getLine(lineId)?.label ?? 'الخط';

  /// `lineNumber` of a rendered line, else the last number seen for that id
  /// this process, else `null`. Used by the reprint side band.
  int? lineNumberForLineId(int lineId) =>
      _lineStates[lineId]?.lineNumber ?? _lastKnownLineNumbers[lineId];

  /// Selected rendered line id (tabs mode); `null` when no line is rendered.
  int? get selectedLineId => _selectedLineId;

  void selectLine(int lineId) {
    if (!isLineRendered(lineId) || _selectedLineId == lineId) return;
    _selectedLineId = lineId;
    notifyListeners();
    // Entering a line re-reads its pending close request (no-op without a
    // palletizer session).
    unawaited(refreshCloseRequest(lineId));
  }

  /// Next usable line (active or needs-PIN) after [fromLineId] in server
  /// order, wrapping around; `null` when no other line is usable.
  int? nextUsableLineId(int fromLineId) {
    final ids = _renderedLineIds;
    final start = ids.indexOf(fromLineId);
    for (var i = 1; i <= ids.length; i++) {
      final id = ids[(start + i) % ids.length];
      if (id == fromLineId) continue;
      final ui = getUiState(id);
      if (ui == LineUiState.active || ui == LineUiState.needsPalletizerAuth) {
        return id;
      }
    }
    return null;
  }

  bool get hasPendingLineNotices => _lineNotices.isNotEmpty;

  /// Drains the pending line add/remove notices (oldest first).
  List<LineAvailabilityNotice> takeLineNotices() {
    final out = List<LineAvailabilityNotice>.of(_lineNotices);
    _lineNotices.clear();
    return out;
  }

  bool get isCreating => _lineCreating.values.any((v) => v);

  // ── Per-line getters ──

  bool isLineAuthorized(int lineId) =>
      _lineStates[lineId]?.isAuthorized ?? false;

  Operator? getAuthorizedOperator(int lineId) =>
      _lineStates[lineId]?.authorizedOperator;

  PalletizerSessionState? getPalletizerSessionState(int lineId) =>
      _palletizerSessions[lineId];

  PalletizerSession? getPalletizerSession(int lineId) =>
      _palletizerSessions[lineId]?.session;

  bool isPalletizerAuthenticating(int lineId) =>
      _palletizerSessions[lineId]?.isAuthenticating ?? false;

  String? getPalletizerName(int lineId) =>
      _palletizerSessions[lineId]?.session?.palletizerName;

  String? getPalletizerAuthError(int lineId) =>
      _palletizerSessions[lineId]?.authError;

  String? getPalletizerAuthErrorCode(int lineId) =>
      _palletizerSessions[lineId]?.authErrorCode;

  bool hasActivePalletizerSession(int lineId) =>
      _palletizerSessions[lineId]?.hasActiveSession ?? false;

  List<SessionTableRow> getSessionTable(int lineId) =>
      _sessionTables[lineId] ?? [];

  /// Bumped every time the backend reports different shift-summary rows for
  /// [lineId] (pallet created, cancelled, quantity edited, …).
  int sessionDataRevision(int lineId) => _sessionDataRevision[lineId] ?? 0;

  /// The current Thermoforming Production Plan item product, hydrated by
  /// [_resolveProductType] strictly from the plan-item fields on the line
  /// state. Returns `null` when there is no active plan item — the UI must
  /// render a no-plan blocked state in that case, never an old product.
  ProductType? getCurrentPlanItemProductType(int lineId) =>
      _planItemProducts[lineId];

  /// Product type id of the current Thermoforming Production Plan item; the
  /// ONLY id the Palletizing App is allowed to send in a create-pallet
  /// request. `null` means the line has no active plan item, and create-pallet
  /// must be disabled.
  int? getCurrentPlanItemProductTypeId(int lineId) =>
      _lineStates[lineId]?.currentPlanItemProductTypeId;

  /// Label of the current Thermoforming Production Plan item's product, or
  /// `null` when the line state carries no plan-item product.
  String? getCurrentPlanItemProductName(int lineId) {
    final state = _lineStates[lineId];
    final backendName = state?.currentPlanItemProductName;
    if (state == null || backendName == null || backendName.trim().isEmpty) {
      return null;
    }
    return productDisplayName(
      productTypeId: state.currentPlanItemProductTypeId,
      backendName: backendName,
    );
  }

  /// `true` when the backend reports the line is blocked specifically by
  /// production-plan state (no plan item / paused / target rules). V81
  /// classifies this as a defensive fallback — under the normal flow the line
  /// also has no active operator and the waiting-for-operator overlay covers
  /// the UI — but the create-pallet button must still react to it.
  /// Id of the line's current plan item — the `expectedPlanItemId` every
  /// create-pallet request must carry (V190). `null` when there is none.
  int? getCurrentPlanItemId(int lineId) =>
      _lineStates[lineId]?.currentPlanItemId;

  bool isProductionPlanBlocked(int lineId) =>
      _lineStates[lineId]?.productionPlanBlocked ?? false;

  /// Localized message backing [isProductionPlanBlocked]. Returns the backend
  /// `productionPlanBlockedMessage` when present, otherwise a safe Arabic
  /// fallback so the UI never shows an empty block.
  String? getProductionPlanBlockedMessage(int lineId) {
    final s = _lineStates[lineId];
    if (s == null || !s.productionPlanBlocked) return null;
    final msg = s.productionPlanBlockedMessage;
    if (msg != null && msg.trim().isNotEmpty) return msg;
    return 'لا يوجد بند إنتاج نشط لهذا الخط. '
        'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.';
  }

  /// packages-per-pallet from the current Thermoforming Production Plan item
  /// (V79), or `null` when the line has no active plan item — in which case
  /// callers fall back to `ProductType.packageQuantity` only when the backend
  /// said `defaultPackageQuantitySource == "PRODUCT_TYPE"`.
  int? getCurrentPlanItemPackagesPerPallet(int lineId) =>
      _lineStates[lineId]?.currentPlanItemPackagesPerPallet;

  /// `"PLAN_ITEM"` / `"PRODUCT_TYPE"` — which source the backend default came
  /// from. Drives whether the UI may fall back to ProductType.packageQuantity.
  String? getDefaultPackageQuantitySource(int lineId) =>
      _lineStates[lineId]?.defaultPackageQuantitySource;

  /// Backend-authoritative (V81+, 2026-05-21): `true` when the line is
  /// thermoforming-linked but has no active operator session. Drives the
  /// [ThermoformingWaitingCard] overlay via [getUiState].
  bool isWaitingForOperator(int lineId) =>
      _lineStates[lineId]?.waitingForOperator ?? false;

  /// Localized title from `LineStateResponse.waitingForOperatorMessageTitle`,
  /// or `null` when not provided (or whitespace-only) — in which case
  /// [ThermoformingWaitingCard] uses its hardcoded Arabic fallback.
  String? getWaitingForOperatorTitle(int lineId) {
    final s = _lineStates[lineId]?.waitingForOperatorMessageTitle;
    return (s != null && s.trim().isNotEmpty) ? s : null;
  }

  /// Localized body from `LineStateResponse.waitingForOperatorMessage`,
  /// or `null` when not provided (or whitespace-only) — in which case
  /// [ThermoformingWaitingCard] uses its hardcoded Arabic fallback.
  String? getWaitingForOperatorMessage(int lineId) {
    final s = _lineStates[lineId]?.waitingForOperatorMessage;
    return (s != null && s.trim().isNotEmpty) ? s : null;
  }

  PalletCreateResponse? getLastPalletResponse(int lineId) =>
      _lastPalletResponses[lineId];

  String? getBlockedReason(int lineId) => _blockedReasons[lineId];

  bool isLineCreating(int lineId) => _lineCreating[lineId] ?? false;

  String? getLineError(int lineId) => _lineErrors[lineId];

  String? getLineUiMode(int lineId) => _lineUiModes[lineId];

  FaletResponse? getFaletItems(int lineId) => _faletItems[lineId];

  bool isFaletItemsLoading(int lineId) => _faletItemsLoading[lineId] ?? false;

  bool hasOpenFalet(int lineId) => _hasOpenFalet[lineId] ?? false;

  int getOpenFaletCount(int lineId) => _openFaletCount[lineId] ?? 0;

  bool isFirstPalletContextLoading(int lineId) =>
      _firstPalletContextLoading[lineId] ?? false;

  // ── Takeover getters ──

  /// Current takeover request for the line, or `null` when there is none.
  TakeoverRequest? getTakeover(int lineId) => _takeovers[lineId];

  /// True while a takeover is PENDING or ACCEPTED (still live).
  bool hasActiveTakeover(int lineId) =>
      _takeovers[lineId]?.status.isActive ?? false;

  /// True whenever the line has any takeover state that should keep the poll
  /// on its fast cadence and a banner on screen.
  bool hasAnyTakeoverActivity(int lineId) => _takeovers[lineId] != null;

  /// True when the screen still needs to show the blocking takeover dialog
  /// for this line (not yet acknowledged).
  bool isTakeoverDialogPending(int lineId) =>
      _pendingDialogLines.contains(lineId);

  // ── Plan-item close handshake getters ──

  /// The line's active close request (WAITING or COMPLETING), or `null`.
  PlanItemCloseRequest? getActiveCloseRequest(int lineId) =>
      _closeRequests[lineId];

  bool get hasAnyActiveCloseRequest =>
      _renderedLineIds.any(_closeRequests.containsKey);

  /// First rendered line (server order) whose request waits for the
  /// palletizer's decision — the line the blocking dialog is shown for.
  int? firstLineAwaitingCloseDecision() {
    for (final lineId in _renderedLineIds) {
      if (_closeRequests[lineId]?.isWaitingForDecision ?? false) return lineId;
    }
    return null;
  }

  bool isCloseRequestDecisionInFlight(int lineId) =>
      _closeDecisionInFlight.contains(lineId);

  String? getCloseRequestDecisionError(int lineId) =>
      _closeDecisionErrors[lineId];

  bool get hasPendingCloseRequestNotices => _closeRequestNotices.isNotEmpty;

  /// Drains the pending close-request notices (oldest first).
  List<CloseRequestNotice> takeCloseRequestNotices() {
    final out = List<CloseRequestNotice>.of(_closeRequestNotices);
    _closeRequestNotices.clear();
    return out;
  }

  /// Pallet creation must be blocked. Combines the existing line-UI blocks
  /// with takeover-specific blocking. Kept SEPARATE from [getUiState] so a
  /// takeover never renders as the legacy-handover overlay.
  ///
  /// PENDING / ACCEPTED do **not** block on their own — only the backend
  /// `blocked` flag or an auto-released line does.
  bool isPalletCreationBlocked(int lineId) {
    if (isLineBlocked(lineId)) return true;
    if (_lineBlockedFlag[lineId] == true) return true;
    final t = _takeovers[lineId];
    if (t != null && t.status.isAutoReleased) return true;
    return false;
  }

  bool isLineBlocked(int lineId) {
    final ui = getUiState(lineId);
    return ui == LineUiState.blocked ||
        ui == LineUiState.pendingHandoverIncoming ||
        ui == LineUiState.pendingHandoverReview ||
        ui == LineUiState.waitingForThermoforming ||
        ui == LineUiState.needsPalletizerAuth;
  }

  /// Single source of truth for the per-line UI branch.
  ///
  /// **Key rule**: `isAuthorized` alone is not sufficient. If the backend
  /// returns `authorized: true` but no `authorizedOperator` data (e.g. the
  /// Thermoforming Operator ended the shift and the authorization row is
  /// stale), the line is still treated as `waitingForThermoforming` so the
  /// blocking overlay appears.
  LineUiState getUiState(int lineId) {
    // 1. Pending legacy handover — a dedicated flow with its own overlay. It
    //    must win even over "no operator": during a handover the line is
    //    transiently unauthorized by design.
    //
    //    Routing accepts two equivalent signals from the backend:
    //      • `lineUiMode == PENDING_HANDOVER_*` — the canonical UI-mode flag.
    //      • `blockedReason in {PENDING_HANDOVER, LINE_BLOCKED_BY_PENDING_HANDOVER}`
    //        — what the backend stamps on `blocked=true` line-state responses
    //        in the new V81+ workflow when the legacy UI-mode field isn't set.
    //        Without the blockedReason fallback such a line would slide into
    //        the generic `blocked` branch and the worker would see no
    //        actionable explanation (or, worse, a misleading credentials
    //        message bubbling up from a downstream API call).
    final mode = _lineUiModes[lineId];
    final reason = _blockedReasons[lineId];
    if (mode == 'PENDING_HANDOVER_NEEDS_INCOMING') {
      return LineUiState.pendingHandoverIncoming;
    }
    if (mode == 'PENDING_HANDOVER_REVIEW' ||
        reason == 'PENDING_HANDOVER' ||
        reason == 'LINE_BLOCKED_BY_PENDING_HANDOVER') {
      return LineUiState.pendingHandoverReview;
    }

    // 1b. Backend-canonical "AUTHORIZED" signal — V81+ live shape.
    //
    // When the backend explicitly stamps `lineUiMode=AUTHORIZED` we trust
    // that as the source of truth and do NOT fall through to the
    // "missing authorization object → waiting" defensive check below.
    // The live production response confirms `authorized=true`,
    // `blocked=false`, `lineUiMode=AUTHORIZED` without always shipping a
    // populated `authorization` object — under the old logic the line would
    // route to `waitingForThermoforming` and the worker would never see the
    // active production UI, even though the line is fully usable.
    //
    // The defensive `waitingForThermoforming` check just below is still
    // exercised for any line where `lineUiMode` is absent (legacy / pre-V81+
    // servers), so the existing no-operator regression tests keep passing.
    if (mode == 'AUTHORIZED') {
      final ls = _lineStates[lineId];
      if (ls != null && ls.isAuthorized && !ls.blocked) {
        if (!hasActivePalletizerSession(lineId)) {
          return LineUiState.needsPalletizerAuth;
        }
        return LineUiState.active;
      }
    }

    // 2. No active Thermoforming Operator on the line.
    //
    //    Deliberately checked BEFORE the generic `blockedReason`: the backend
    //    reports a line with no operator as `authorized: false` /
    //    `authorization: null` AND commonly *also* stamps a `blockedReason`
    //    (e.g. `LINE_NOT_AUTHORIZED`). With the old ordering `blockedReason`
    //    won, getUiState returned `LineUiState.blocked` — a state for which
    //    ProductionLineSection renders NO overlay — so the bare grey
    //    "غير متوفر" cards stayed on screen and the blocking
    //    ThermoformingWaitingCard never appeared. A line with no operator is
    //    unusable regardless of any other block, and "no operator" is the
    //    most specific, actionable explanation, so it takes precedence.
    //
    //    V81+ (2026-05-21): `lineState.waitingForOperator` is the canonical
    //    backend-authoritative signal — set whenever a thermoforming-linked
    //    line has no active LineOperatorAuthorization. The derived clauses
    //    `!isAuthorized` / `authorizedOperator == null` are kept as
    //    defense-in-depth for non-thermoforming-linked lines (where the
    //    backend never sets the new flag) and pre-V81+ servers. They also
    //    keep matching the exact fields that make LineContextStrip render
    //    "المشغّل: غير متوفر", so the overlay always shows when that text
    //    would.
    final lineState = _lineStates[lineId];
    if (lineState == null ||
        lineState.waitingForOperator ||
        !lineState.isAuthorized ||
        lineState.authorizedOperator == null) {
      return LineUiState.waitingForThermoforming;
    }

    // 3. Backend-authoritative block for a line that DOES have an operator
    //    (equipment fault, admin block, …) — kept distinct so a real block is
    //    never silently relabelled as "no operator". `reason` is the same
    //    value read at the top of this function.
    if ((reason ?? '').isNotEmpty) {
      return LineUiState.blocked;
    }

    // 4. Authorized + operator present.
    if (!hasActivePalletizerSession(lineId)) {
      return LineUiState.needsPalletizerAuth;
    }
    return LineUiState.active;
  }

  /// Every backend lineId this station currently renders. Read-only snapshot
  /// consumed by [ManagerAnnouncementNotifier] to fetch / ack the domain-wide
  /// urgent notice — never includes a line that is not drawn. Empty until
  /// bootstrap has loaded.
  List<int> get knownOperatingLineIds => renderedLineIds;

  // ── Adaptive polling ──

  /// `true` when the most recent poll round failed for every line.
  bool get lastPollFailed => _lastPollFailed;

  /// `true` when [lineId] is in a state that demands fast polling: blocked
  /// by the backend, mid legacy-handover, mid-takeover (including the
  /// auto-released terminal states), or waiting for the Thermoforming operator
  /// (no active operator). Steady `active` and `needsPalletizerAuth` lines are
  /// NOT urgent.
  ///
  /// Exposed as a simple boolean so the screen never has to reason about the
  /// individual backend fields.
  bool hasUrgentLineState(int lineId) {
    // A line that is not rendered can never force the fast cadence.
    if (!isLineRendered(lineId)) return false;

    // Backend-authoritative blocked flag / reason.
    if (_lineBlockedFlag[lineId] == true) return true;
    if ((_blockedReasons[lineId] ?? '').isNotEmpty) return true;

    // Pending legacy handover.
    final mode = _lineUiModes[lineId];
    if (mode == 'PENDING_HANDOVER_NEEDS_INCOMING' ||
        mode == 'PENDING_HANDOVER_REVIEW') {
      return true;
    }

    // Any takeover request — pending, accepted, or auto-released — keeps the
    // poll fast so the banner / dialog / countdown stay responsive. This
    // mirrors `pendingTakeoverRequest != null` / `takeoverRequestStatus`.
    if (_takeovers[lineId] != null) return true;

    // Waiting for the Thermoforming operator (no active operator) or a
    // blocked / handover UI branch.
    switch (getUiState(lineId)) {
      case LineUiState.waitingForThermoforming:
      case LineUiState.blocked:
      case LineUiState.pendingHandoverIncoming:
      case LineUiState.pendingHandoverReview:
        return true;
      case LineUiState.needsPalletizerAuth:
      case LineUiState.active:
        return false;
    }
  }

  /// `true` when any rendered line is urgent — drives [PollCadence.urgent].
  bool get hasAnyUrgentLineState => _renderedLineIds.any(hasUrgentLineState);

  /// Cadence bucket for the next poll. Urgent always wins; a fully failed
  /// round backs off to [PollCadence.retry]; while SSE is down the
  /// [PollCadence.fallback] cadence is the only refresh channel; with SSE
  /// connected, an active close request keeps [PollCadence.closeRequestPending]
  /// and otherwise [PollCadence.safety] is just a slow safety net.
  PollCadence get pollCadence {
    if (hasAnyUrgentLineState) return PollCadence.urgent;
    if (_lastPollFailed) return PollCadence.retry;
    if (_sseState != SseConnectionState.connected) return PollCadence.fallback;
    if (hasAnyActiveCloseRequest) return PollCadence.closeRequestPending;
    return PollCadence.safety;
  }

  /// Interval the [RefreshCoordinator] waits before scheduling the next poll.
  Duration get nextPollInterval => pollCadence.interval;

  /// Latest device-level SSE connection state.
  SseConnectionState get sseConnectionState => _sseState;

  // ── SSE-driven refresh ──

  /// Forwarded from the [SseClient] connection-state stream. Updates the
  /// cadence input then lets the coordinator reschedule + run an immediate
  /// refresh on (re)connect.
  void onSseConnectionStateChanged(SseConnectionState state) {
    final changed = _sseState != state;
    _sseState = state;
    if (changed) notifyListeners();
    _coordinator?.onSseConnectionStateChanged(state);
  }

  /// Handles one debounced batch of `palletizing-lines-changed` frames
  /// (LINE_3 handoff §4.4 / §6.5). Never shows the loading shimmer.
  ///
  /// A silent bootstrap re-fetch — which covers every line — runs when any
  /// frame
  ///   * has no `palletizingLineId`,
  ///   * names a line that is not rendered (this is how an enabled line
  ///     appears), or
  ///   * carries reason `LINE_STATE_CHANGED` (enable / disable of a rendered
  ///     line produces exactly this frame).
  /// Otherwise each rendered line named in the batch refreshes its `/state`.
  ///
  /// Routing uses `palletizingLineId` only — `thermoformingLineId` is a
  /// different id space (TF_LINE_3 is 4 while LINE_3 is 3).
  ///
  /// A `PLAN_ITEM_CLOSE_*` frame also forces a re-read of the line's pending
  /// close request (the frame itself carries no request state).
  ///
  /// A `PALLET_GRINDING_CHANGED` frame bumps the line's session revision so an
  /// open drill-down re-reads its pallets (grinding chip, label marker,
  /// reprint permission) — the session table's counts do not change, so the
  /// `/state` refresh alone would not.
  Future<void> refreshFromSseEvents(List<PalletizingAppSseEvent> events) async {
    var needsBootstrap = false;
    final lineIds = <int>{};
    final closeRequestLineIds = <int>{};
    final grindingLineIds = <int>{};
    for (final event in events) {
      final lineId = event.palletizingLineId;
      if (lineId != null &&
          isLineRendered(lineId) &&
          _isPlanItemCloseReason(event.reason)) {
        closeRequestLineIds.add(lineId);
        _recordCloseRequestSseHint(lineId, event.reason!);
      }
      if (lineId != null && event.reason == 'PALLET_GRINDING_CHANGED') {
        grindingLineIds.add(lineId);
      }
      if (lineId == null ||
          !isLineRendered(lineId) ||
          event.reason == 'LINE_STATE_CHANGED') {
        needsBootstrap = true;
      } else {
        lineIds.add(lineId);
      }
    }
    _closeRequestForced.addAll(closeRequestLineIds);
    if (needsBootstrap) {
      await refreshBootstrap();
      if (_bumpSessionRevisions(grindingLineIds)) notifyListeners();
      return;
    }
    await Future.wait(lineIds.map(_refreshLineStateFromBackend));
    // A `/state` refresh that was overtaken skips the session sync, so make
    // sure every nudged line still re-reads its request (no-op when the sync
    // already consumed the force flag).
    await Future.wait(
      closeRequestLineIds
          .where(_closeRequestForced.contains)
          .map(refreshCloseRequest),
    );
    _bumpSessionRevisions(grindingLineIds);
    notifyListeners();
  }

  /// Marks the session detail of each rendered line in [lineIds] as changed,
  /// so listeners (the drill-down) re-read it on the next notification.
  /// Returns whether any line was bumped.
  bool _bumpSessionRevisions(Iterable<int> lineIds) {
    var bumped = false;
    for (final lineId in lineIds) {
      if (!isLineRendered(lineId)) continue;
      _sessionDataRevision[lineId] = sessionDataRevision(lineId) + 1;
      bumped = true;
    }
    return bumped;
  }

  // ── Refresh loop lifecycle (forwarded from the screen) ──

  /// Starts the SSE stream + adaptive poll loop. Called once after the first
  /// [loadBootstrap]. Idempotent.
  void startRefreshLoop() => _coordinator?.start();

  /// Pauses the loop while the app is backgrounded.
  void pauseRefreshLoop() => _coordinator?.pause();

  /// Resumes the loop when the app returns to the foreground; runs one
  /// immediate refresh internally.
  void resumeRefreshLoop() => _coordinator?.resume();

  /// Stops the loop (logout / teardown).
  void stopRefreshLoop() => _coordinator?.stop();

  /// Clears transient polling / refresh bookkeeping. Called on logout so a
  /// stale `retry` cadence or line error never leaks into the next session.
  void clearTransientRefreshState() {
    _lastPollFailed = false;
    _lineErrors.clear();
    notifyListeners();
  }

  // ── Bootstrap ──

  /// First launch / manual Refresh: shows the loading shimmer, then runs the
  /// shared single-flight bootstrap.
  Future<void> loadBootstrap() async {
    _state = PalletizingState.loading;
    _errorMessage = null;
    notifyListeners();
    await refreshBootstrap();
  }

  /// Silent bootstrap re-fetch — no loading state, no shimmer. Used for SSE
  /// frames, (re)connect, resume and the safety tick.
  ///
  /// Single-flight: a call made while one is in flight joins it and schedules
  /// exactly one trailing re-fetch, so a trigger that arrived after the
  /// in-flight request left is never lost and responses can never apply out
  /// of order. Adds / removes lines by `lineId`, prunes removed lines from
  /// all per-line state and keeps the selection.
  Future<void> refreshBootstrap() {
    final inFlight = _bootstrapInFlight;
    if (inFlight != null) {
      _bootstrapRerunRequested = true;
      return inFlight;
    }
    final run = _runBootstrapLoop();
    _bootstrapInFlight = run;
    return run;
  }

  Future<void> _runBootstrapLoop() async {
    try {
      do {
        _bootstrapRerunRequested = false;
        await _fetchAndApplyBootstrap();
      } while (_bootstrapRerunRequested);
    } finally {
      _bootstrapInFlight = null;
    }
  }

  Future<void> _fetchAndApplyBootstrap() async {
    // A silent refresh that fails keeps the rendered lines; only a load that
    // is already on the shimmer / error surface reports the failure there.
    final surfaceErrors = _state != PalletizingState.loaded;
    final requestGen = ++_lineStateRequestGen;
    try {
      final bootstrap = await _repository.bootstrap();
      await _applyBootstrap(bootstrap, requestGen);

      _state = PalletizingState.loaded;
      _lastBootstrapAt = _clock();
      // A successful bootstrap is also a successful round trip — clear any
      // earlier network-failure back-off and any device-key error from a
      // previous attempt. Without this, a screen that was just showing the
      // device-key recovery surface would not transition back to the normal
      // production UI after the key was re-validated.
      _lastPollFailed = false;
      _deviceKeyInvalid = false;
      _errorMessage = null;
      if (kDebugMode) {
        debugPrint(
          '[Bootstrap OK] lines=${bootstrap.lines.length} '
          'rendered=$_renderedLineIds '
          'productTypes=${bootstrap.productTypes.length}',
        );
        for (final l in bootstrap.lines) {
          debugPrint(
            '[Bootstrap OK] line=${l.lineNumber} id=${l.lineId} '
            'authorized=${l.isAuthorized} blocked=${l.blocked} '
            'blockedReason=${l.blockedReason ?? "null"} '
            'lineUiMode=${l.lineUiMode ?? "null"} '
            'waitingForOperator=${l.waitingForOperator} '
            'pendingHandover=${l.lineUiMode?.startsWith("PENDING_HANDOVER") ?? false}',
          );
        }
      }
    } on ApiException catch (e) {
      _lastPollFailed = true;
      if (surfaceErrors) {
        // DEVICE_KEY_INVALID is a distinct, recoverable state — the screen
        // renders an "Open Device Settings" CTA instead of the generic retry
        // button so a misconfigured device is never mistaken for a transient
        // backend outage.
        _deviceKeyInvalid = e.code == 'DEVICE_KEY_INVALID';
        _errorMessage = e.displayMessage;
        _state = PalletizingState.error;
      }
      debugPrint(
        'PalletizingProvider bootstrap error: ${e.code} - ${e.message} '
        '(status=${e.statusCode ?? "n/a"}, silent=${!surfaceErrors})',
      );
    } catch (e, stackTrace) {
      _lastPollFailed = true;
      if (surfaceErrors) {
        _deviceKeyInvalid = false;
        _errorMessage = 'فشل في تحميل البيانات: $e';
        _state = PalletizingState.error;
      }
      debugPrint('PalletizingProvider bootstrap unexpected error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    notifyListeners();
  }

  Future<void> _applyBootstrap(
    BootstrapResponse bootstrap,
    int requestGen,
  ) async {
    _productTypes = bootstrap.productTypes;
    _productTypesById = {for (final p in bootstrap.productTypes) p.id: p};

    final previousIds = _renderedLineIds;
    final previousLabels = {for (final id in previousIds) id: lineLabel(id)};
    final previousSelection = _selectedLineId;

    // Server order, de-duplicated by lineId (the key), never re-sorted.
    final nextIds = <int>[];
    for (final line in bootstrap.lines) {
      if (!nextIds.contains(line.lineId)) nextIds.add(line.lineId);
    }
    final removedIds = previousIds
        .where((id) => !nextIds.contains(id))
        .toList();
    final addedIds = nextIds.where((id) => !previousIds.contains(id)).toList();

    _renderedLineIds = List.unmodifiable(nextIds);
    for (final id in removedIds) {
      _pruneLine(id);
    }

    for (final lineState in bootstrap.lines) {
      // A `/state` read sent after this bootstrap and already applied is
      // fresher — keep it rather than rolling the line back.
      _applyLineStateIfNewer(lineState.lineId, lineState, requestGen);
    }

    if (previousSelection == null || !nextIds.contains(previousSelection)) {
      _selectedLineId = nextIds.isEmpty ? null : nextIds.first;
    }

    if (_hasAppliedBootstrap) {
      for (final id in removedIds) {
        _lineNotices.add(
          LineAvailabilityNotice(
            change: LineAvailabilityChange.removed,
            lineId: id,
            label: previousLabels[id] ?? 'الخط',
            wasSelected: id == previousSelection,
          ),
        );
      }
      for (final id in addedIds) {
        _lineNotices.add(
          LineAvailabilityNotice(
            change: LineAvailabilityChange.added,
            lineId: id,
            label: lineLabel(id),
          ),
        );
      }
    }
    _hasAppliedBootstrap = true;
    if (removedIds.isNotEmpty || addedIds.isNotEmpty) {
      debugPrint(
        '[Bootstrap LINES] rendered=$nextIds added=$addedIds '
        'removed=$removedIds',
      );
    }

    // Prime the session-token gate before any session refresh so a cold
    // start with no stored token makes zero `/palletizer-session/current`
    // calls.
    await _primeSessionTokenCache();

    // Bootstrap runs on app start, resume, SSE (re)connect, manual refresh
    // and the safety tick — every one of them must re-read pending close
    // requests (frames may have been missed).
    _closeRequestForced.addAll(nextIds);

    // For every authorized line, sync the palletizer session from the
    // backend + secure storage so cold start lands directly in State C when a
    // session is still alive. Each call is internally gated by
    // [_mayHavePalletizerSession] — lines with no stored token are skipped.
    await Future.wait(
      bootstrap.lines
          .where((l) => l.isAuthorized)
          .map((l) => refreshPalletizerSession(l.lineId)),
    );
  }

  /// Removes every trace of a line that left bootstrap. Stored palletizer
  /// tokens are kept — they are re-validated by `/palletizer-session/current`
  /// if the line comes back.
  void _pruneLine(int lineId) {
    _lineStates.remove(lineId);
    _palletizerSessions.remove(lineId);
    _sessionTables.remove(lineId);
    _planItemProducts.remove(lineId);
    _lastPalletResponses.remove(lineId);
    _blockedReasons.remove(lineId);
    _lineCreating.remove(lineId);
    _lineErrors.remove(lineId);
    _lineUiModes.remove(lineId);
    _faletItems.remove(lineId);
    _faletItemsLoading.remove(lineId);
    _hasOpenFalet.remove(lineId);
    _openFaletCount.remove(lineId);
    _firstPalletContextLoading.remove(lineId);
    _takeovers.remove(lineId);
    _lineBlockedFlag.remove(lineId);
    _pendingDialogLines.remove(lineId);
    _lineStateAppliedGen.remove(lineId);
    _sessionDataRevision.remove(lineId);
    _maybeHasPalletizerSession.remove(lineId);
    _clearCloseRequestState(lineId);
    _closeRequestSeq.remove(lineId);
    _closeRequestNotices.removeWhere((n) => n.lineId == lineId);
  }

  /// `PRODUCTION_LINE_INACTIVE` / `PRODUCTION_LINE_NOT_FOUND` mean this app's
  /// line list is out of date — re-fetch bootstrap so the tab disappears.
  static bool _isStaleLineError(ApiException e) =>
      e.code == 'PRODUCTION_LINE_INACTIVE' ||
      e.code == 'PRODUCTION_LINE_NOT_FOUND';

  // ── Refresh single line state ──

  /// Refreshes one rendered line from `/state`. A line that is not rendered
  /// is never requested — `/state` does not check `is_active`, so polling it
  /// could not tell a disabled line apart from a live one.
  Future<void> refreshLineState(int lineId) async {
    if (!isLineRendered(lineId)) return;
    await _refreshLineStateFromBackend(lineId);
    notifyListeners();
  }

  /// Refreshes one line from `/state`. Returns `true` when the backend call
  /// succeeded and `false` on any network / timeout / API failure —
  /// [pollLineMonitoring] aggregates this into the retry cadence.
  ///
  /// Overlapping reads for the same line (an SSE-driven refresh racing a
  /// safety poll or a bootstrap, say) are made order-safe by
  /// [_applyLineStateIfNewer]: a response whose request was sent before the
  /// one already applied is dropped, so a slow out-of-order response can never
  /// overwrite fresher state. A dropped response still counts as success — the
  /// network round-trip worked. A response for a line that left bootstrap
  /// while in flight is dropped too.
  Future<bool> _refreshLineStateFromBackend(int lineId) async {
    final requestGen = ++_lineStateRequestGen;
    try {
      final lineState = await _repository.getLineState(lineId);

      // Overtaken by a newer applied read — keep that one, skip the session
      // sync below.
      if (!isLineRendered(lineId) ||
          !_applyLineStateIfNewer(lineId, lineState, requestGen)) {
        return true;
      }

      // Re-sync the palletizer session whenever line state changes so we drop
      // back to State B if the backend ended the session (e.g. shift-line ended).
      if (lineState.isAuthorized) {
        await refreshPalletizerSession(lineId);
      } else {
        // Line was de-authorized — the bound palletizer session is gone too.
        await _dropToStateB(lineId);
      }
      return true;
    } on ApiException catch (e) {
      debugPrint('Failed to refresh line $lineId state: ${e.code}');
      // Unknown id → the line list is stale; bootstrap decides what to draw.
      if (_isStaleLineError(e)) unawaited(refreshBootstrap());
      return false;
    } catch (e) {
      debugPrint('Failed to refresh line $lineId state: $e');
      return false;
    }
  }

  /// Resolves the product the UI is allowed to surface for the line.
  ///
  /// SOURCE OF TRUTH: the current Thermoforming Production Plan item — only.
  /// Returns `null` when there is no active plan item; the caller must render
  /// a no-plan / blocked state in that case.
  ProductType? _resolveProductType(BootstrapLineState lineState) {
    final planProductId = lineState.currentPlanItemProductTypeId;
    final planProductName = lineState.currentPlanItemProductName;
    if (planProductId == null) return null;

    // Prefer the rich ProductType from the reference catalog (carries
    // packageQuantity, color, image, etc.) so the UI has full metadata.
    final match = _productTypes.where((p) => p.id == planProductId).firstOrNull;
    if (match != null) return match;

    // Catalog miss (rare — admin can add a product mid-shift). Fall back to a
    // minimal product type built from the plan-item fields on the line state
    // so the UI still shows the plan-item name.
    if (planProductName != null && planProductName.isNotEmpty) {
      return ProductType(
        id: planProductId,
        name: planProductName,
        productName: ProductType.resolveDisplayName(
          backendName: planProductName,
        ),
        prefix: '',
        color: '',
        packageQuantity: lineState.currentPlanItemPackagesPerPallet ?? 0,
        packageUnit: '',
        packageUnitDisplayName: '',
      );
    }
    return null;
  }

  /// Hydrates [lineState] unless a read sent after [requestGen] has already
  /// been applied for [lineId]. Returns whether it was applied.
  bool _applyLineStateIfNewer(
    int lineId,
    BootstrapLineState lineState,
    int requestGen,
  ) {
    final applied = _lineStateAppliedGen[lineId];
    if (applied != null && applied > requestGen) return false;
    _lineStateAppliedGen[lineId] = requestGen;
    _hydrateLineState(lineId, lineState);
    return true;
  }

  void _hydrateLineState(int lineId, BootstrapLineState lineState) {
    _lineStates[lineId] = lineState;
    _lastKnownLineNumbers[lineId] = lineState.lineNumber;
    final previousRows = _sessionTables[lineId];
    _sessionTables[lineId] = lineState.sessionTable;
    if (previousRows != null &&
        !listEquals(previousRows, lineState.sessionTable)) {
      _sessionDataRevision[lineId] = sessionDataRevision(lineId) + 1;
    }
    _blockedReasons[lineId] = lineState.blockedReason;
    _lineUiModes[lineId] = lineState.lineUiMode;
    _hasOpenFalet[lineId] = lineState.hasOpenFalet;
    _openFaletCount[lineId] = lineState.openFaletCount;
    _planItemProducts[lineId] = _resolveProductType(lineState);
    _palletizerSessions[lineId] ??= PalletizerSessionState.empty(lineId);
    _lineBlockedFlag[lineId] = lineState.blocked;
    _applyTakeoverState(lineId, lineState.pendingTakeoverRequest);

    // Clear a stale palletizer-auth error whenever the line is no longer in
    // the PIN-entry branch. Without this, a previous "wrong PIN" message stays
    // pinned to the session state and pops back up the moment the line cycles
    // through a handover / blocked / waiting branch and then lands on
    // `needsPalletizerAuth` again — exactly the wrong moment to surface a
    // credential-style error on a workflow transition.
    final session = _palletizerSessions[lineId];
    if (session != null && session.authError != null) {
      final newUi = getUiState(lineId);
      if (newUi != LineUiState.needsPalletizerAuth) {
        _palletizerSessions[lineId] = session.copyWith(clearAuthError: true);
      }
    }

    // ── Temporary diagnostic (debug builds only) ──────────────────────────
    // Logs the raw backend fields that drive [getUiState] every time a line
    // is hydrated (bootstrap + each poll). Use this to confirm on-device why
    // a line routes to a given LineUiState — e.g. a no-operator line that
    // also carries a `blockedReason`. Safe to delete once verified; compiled
    // out of release builds by `kDebugMode`.
    if (kDebugMode) {
      debugPrint(
        '[LineUiState] lineId=$lineId number=${lineState.lineNumber} '
        'isAuthorized=${lineState.isAuthorized} '
        'authorizedOperator=${lineState.authorizedOperator?.displayLabel ?? 'null'} '
        'waitingForOperator=${lineState.waitingForOperator} '
        'blockedReason=${lineState.blockedReason ?? 'null'} '
        'lineUiMode=${lineState.lineUiMode ?? 'null'} '
        'blocked=${lineState.blocked} '
        '=> ${getUiState(lineId)}',
      );
    }
  }

  /// Reconciles the takeover state for a line on every line-state refresh.
  ///
  /// Fires the sound + vibration + blocking dialog **exactly once** per
  /// takeover request id: the id-keyed `_alertedTakeoverIds` / `_acknowledged`
  /// sets ensure a repeated poll never replays the alert, while a genuinely
  /// new request (new id) alerts again. A PENDING→ACCEPTED transition on an
  /// already-alerted id only updates the banner — no new sound, no dialog.
  /// Only a rendered line may alert: a line the tablet does not draw would
  /// ring with no dialog to explain it.
  void _applyTakeoverState(int lineId, TakeoverRequest? incoming) {
    _takeovers[lineId] = incoming;
    if (incoming == null || !isLineRendered(lineId)) {
      _pendingDialogLines.remove(lineId);
      return;
    }

    if (incoming.status.isActive &&
        !_alertedTakeoverIds.contains(incoming.id)) {
      _alertedTakeoverIds.add(incoming.id);
      // Fire-and-forget — failures are swallowed inside the service.
      _notifications.alert();
      if (!_acknowledgedTakeoverIds.contains(incoming.id)) {
        _pendingDialogLines.add(lineId);
      }
    }
  }

  /// Called when the worker taps "حسناً" on the blocking takeover dialog.
  /// Records the request id as acknowledged so a late poll cannot re-pop the
  /// dialog, then collapses it into the persistent banner.
  void acknowledgeTakeover(int lineId) {
    final t = _takeovers[lineId];
    if (t != null) _acknowledgedTakeoverIds.add(t.id);
    _pendingDialogLines.remove(lineId);
    notifyListeners();
  }

  /// Called by the screen right before it shows the dialog, so the same
  /// signal is not consumed twice while the dialog is open.
  void consumeTakeoverDialogSignal(int lineId) {
    _pendingDialogLines.remove(lineId);
  }

  // ── Palletizer auth ──

  Future<bool> palletizerAuth(int lineId, String pin) async {
    if (!isLineRendered(lineId)) return false;

    _palletizerSessions[lineId] =
        (_palletizerSessions[lineId] ?? PalletizerSessionState.empty(lineId))
            .copyWith(isAuthenticating: true, clearAuthError: true);
    notifyListeners();

    try {
      final result = await _repository.palletizerAuth(lineId: lineId, pin: pin);

      // Persist the raw token ONCE — namespaced by backend lineId.
      await _authStorage.savePalletizerSessionToken(
        lineId,
        result.sessionToken,
      );
      // The line was switched off while the PIN was being checked — keep the
      // token (re-validated if the line returns) but no per-line state.
      if (!isLineRendered(lineId)) return true;

      // The app now has a session — re-open the `/palletizer-session/current`
      // gate for this line.
      _maybeHasPalletizerSession[lineId] = true;

      _palletizerSessions[lineId] = PalletizerSessionState(
        lineId: lineId,
        session: result.session,
      );

      // Refresh line state to pick up any backend-side changes (operator name,
      // handover transitions, etc.) — but don't let it stomp the session we
      // just stored.
      try {
        final requestGen = ++_lineStateRequestGen;
        final lineState = await _repository.getLineState(lineId);
        if (isLineRendered(lineId)) {
          _applyLineStateIfNewer(lineId, lineState, requestGen);
        }
      } catch (e) {
        debugPrint('Post-auth line refresh error (line $lineId): $e');
      }

      notifyListeners();
      // A close request sent while nobody was logged in appears right after
      // PIN login (handoff §6 / Appendix D).
      await refreshCloseRequest(lineId);
      return true;
    } on ApiException catch (e) {
      if (!isLineRendered(lineId)) return false;
      _palletizerSessions[lineId] = PalletizerSessionState(
        lineId: lineId,
        isAuthenticating: false,
        authError: e.displayMessageForLine(lineLabel(lineId)),
        authErrorCode: e.code,
      );
      notifyListeners();
      // The line was switched off / removed — bootstrap drops its tab.
      if (_isStaleLineError(e)) await refreshBootstrap();
      return false;
    } catch (e) {
      if (!isLineRendered(lineId)) return false;
      _palletizerSessions[lineId] = PalletizerSessionState(
        lineId: lineId,
        isAuthenticating: false,
        authError: 'فشل في التحقق من الرمز',
      );
      notifyListeners();
      return false;
    }
  }

  /// `true` only when the app already has a local signal that a palletizer
  /// session may exist for the line — a cached active session or a stored
  /// session token. When `false`, `/palletizer-session/current` must not be
  /// called: hitting it without a session is what produced the
  /// `PALLETIZER_SESSION_REQUIRED` log spam.
  bool _mayHavePalletizerSession(int lineId) {
    if (_palletizerSessions[lineId]?.hasActiveSession ?? false) return true;
    return _maybeHasPalletizerSession[lineId] ?? false;
  }

  /// Primes [_maybeHasPalletizerSession] from secure storage once per known
  /// line, so the per-poll gate never has to await secure storage.
  Future<void> _primeSessionTokenCache() async {
    for (final lineId in _renderedLineIds) {
      final token = await _authStorage.getPalletizerSessionToken(lineId);
      _maybeHasPalletizerSession[lineId] = token != null && token.isNotEmpty;
    }
  }

  /// Fetches the current palletizer session from the backend for a given line.
  /// On 404 / PALLETIZER_SESSION_REQUIRED, drops the line to State B and
  /// clears the locally stored token.
  ///
  /// Gated: if the app has no local signal that a session may exist
  /// ([_mayHavePalletizerSession]), the call is skipped entirely — the device
  /// is in the pre-login state and `/palletizer-session/current` would only
  /// 404. The endpoint resumes being called after a successful
  /// [palletizerAuth].
  Future<void> refreshPalletizerSession(int lineId) async {
    if (!isLineRendered(lineId)) return;

    if (!_mayHavePalletizerSession(lineId)) return;

    try {
      final session = await _repository.getCurrentPalletizerSession(lineId);
      if (!isLineRendered(lineId)) return;
      _palletizerSessions[lineId] = PalletizerSessionState(
        lineId: lineId,
        session: session,
      );
      notifyListeners();
      // The session is live — reconcile the pending close request. Forced
      // after bootstrap / SSE nudges, throttled on routine polls.
      await _syncCloseRequest(lineId);
    } on ApiException catch (e) {
      // Treat any of these as "the stored session token is no longer usable —
      // drop the device to State B so the PIN screen takes over": the
      // canonical PALLETIZER_SESSION_REQUIRED, a stale-credential rejection,
      // or a generic UNAUTHORIZED on this single session endpoint. Without the
      // extra codes, a backend that started rejecting an old token with
      // AUTH_INVALID_CREDENTIALS would leave the token in place and keep
      // re-failing every poll — and prior to the fix that error path was the
      // observed source of a stale "بيانات الدخول غير صحيحة" message in the
      // logs after a workflow migration.
      if (e.code == 'PALLETIZER_SESSION_REQUIRED' ||
          e.code == 'AUTH_INVALID_CREDENTIALS' ||
          e.code == 'UNAUTHORIZED') {
        await _dropToStateB(lineId);
      } else {
        debugPrint(
          'refreshPalletizerSession error (line $lineId): ${e.code} - ${e.message}',
        );
      }
    } catch (e) {
      debugPrint(
        'refreshPalletizerSession unexpected error (line $lineId): $e',
      );
    }
  }

  Future<void> palletizerLogout(int lineId) async {
    final token = await _authStorage.getPalletizerSessionToken(lineId);
    if (token != null && token.isNotEmpty) {
      try {
        await _repository.palletizerLogout(lineId: lineId, sessionToken: token);
      } on ApiException catch (e) {
        // Idempotent — any flavor of session-required is treated as success.
        if (e.code != 'PALLETIZER_SESSION_REQUIRED') {
          debugPrint(
            'palletizerLogout error (line $lineId): ${e.code} - ${e.message}',
          );
        }
      } catch (e) {
        debugPrint('palletizerLogout unexpected error (line $lineId): $e');
      }
    }

    await _dropToStateB(lineId);
    // Logout — drop transient polling/error bookkeeping so the next session
    // starts clean (the screen cancels its poll timer separately).
    clearTransientRefreshState();
  }

  /// Clears the local session + secure-storage token and notifies listeners.
  /// Used by logout, by PALLETIZER_SESSION_REQUIRED interception, and by line
  /// de-authorization (operator ended the shift-line).
  Future<void> _dropToStateB(int lineId) async {
    await _authStorage.clearPalletizerSessionToken(lineId);
    // A line pruned meanwhile keeps no per-line state.
    if (!isLineRendered(lineId)) return;
    // No token, no session — close the `/palletizer-session/current` gate so
    // a 404 is never retried in a loop until the next successful auth.
    _maybeHasPalletizerSession[lineId] = false;
    _palletizerSessions[lineId] = PalletizerSessionState.empty(lineId);
    // Logout / session end: the close dialog and banner go away; the request
    // is fetched again after the next PIN login (handoff Appendix B).
    _clearCloseRequestState(lineId);
    notifyListeners();
  }

  void clearPalletizerAuthError(int lineId) {
    final current = _palletizerSessions[lineId];
    if (current != null && current.authError != null) {
      _palletizerSessions[lineId] = current.copyWith(clearAuthError: true);
      notifyListeners();
    }
  }

  // ── Plan-item close handshake (V190) ──

  static const String _planItemCloseReasonPrefix = 'PLAN_ITEM_CLOSE_';
  static const String _reasonCloseConfirmed = 'PLAN_ITEM_CLOSE_CONFIRMED';
  static const String _reasonCloseCancelled =
      'PLAN_ITEM_CLOSE_REQUEST_CANCELLED';
  static const String _reasonCloseInvalidated =
      'PLAN_ITEM_CLOSE_REQUEST_INVALIDATED';

  static bool _isPlanItemCloseReason(String? reason) =>
      reason != null && reason.startsWith(_planItemCloseReasonPrefix);

  /// Remembers a terminal reason while a request is still on screen, so the
  /// notice shown once the REST read confirms it is gone says why.
  void _recordCloseRequestSseHint(int lineId, String reason) {
    if (!_closeRequests.containsKey(lineId)) return;
    if (reason == _reasonCloseConfirmed ||
        reason == _reasonCloseCancelled ||
        reason == _reasonCloseInvalidated) {
      _closeRequestSseHint[lineId] = reason;
    }
  }

  /// Re-reads the line's pending close request now (the authoritative read).
  ///
  /// A no-op for a line that is not rendered or has no active palletizer
  /// session — the read is token-gated and nothing about close requests is
  /// shown before PIN login. Single-flight per line: a call made while a read
  /// is in flight joins it and schedules one trailing re-read.
  Future<void> refreshCloseRequest(int lineId) {
    if (!isLineRendered(lineId) || !hasActivePalletizerSession(lineId)) {
      return Future.value();
    }
    _closeRequestForced.remove(lineId);
    final inFlight = _closeRequestFetches[lineId];
    if (inFlight != null) {
      _closeRequestRefetchRequested.add(lineId);
      return inFlight;
    }
    final run = _runCloseRequestFetchLoop(lineId);
    _closeRequestFetches[lineId] = run;
    return run;
  }

  /// Called after every successful session refresh: re-reads when forced
  /// (bootstrap / SSE nudge), when never read, or when the last read is older
  /// than [closeRequestPollInterval].
  Future<void> _syncCloseRequest(int lineId) {
    final last = _closeRequestFetchedAt[lineId];
    final due =
        _closeRequestForced.contains(lineId) ||
        last == null ||
        _clock().difference(last) >= closeRequestPollInterval;
    return due ? refreshCloseRequest(lineId) : Future.value();
  }

  Future<void> _runCloseRequestFetchLoop(int lineId) async {
    try {
      do {
        _closeRequestRefetchRequested.remove(lineId);
        await _fetchAndApplyCloseRequest(lineId);
      } while (_closeRequestRefetchRequested.contains(lineId) &&
          isLineRendered(lineId));
    } finally {
      _closeRequestFetches.remove(lineId);
      _closeRequestRefetchRequested.remove(lineId);
    }
  }

  Future<void> _fetchAndApplyCloseRequest(int lineId) async {
    final token = await _authStorage.getPalletizerSessionToken(lineId);
    if (token == null || token.isEmpty) return;
    final seq = (_closeRequestSeq[lineId] ?? 0) + 1;
    _closeRequestSeq[lineId] = seq;
    try {
      final fetched = await _repository.getActivePlanItemCloseRequest(
        lineId: lineId,
        sessionToken: token,
      );
      // Overtaken by a newer read or a decision, or the line / session went
      // away while the call was in flight — drop the response untouched.
      if (_closeRequestSeq[lineId] != seq ||
          !isLineRendered(lineId) ||
          !hasActivePalletizerSession(lineId)) {
        return;
      }
      _closeRequestFetchedAt[lineId] = _clock();
      _applyFetchedCloseRequest(lineId, fetched);
    } on ApiException catch (e) {
      if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        // 401 (ended / replaced) or 403 (token of another line) — PIN login.
        await _dropToStateB(lineId);
      } else if (_isStaleLineError(e)) {
        unawaited(refreshBootstrap());
      } else {
        // Network / server trouble: keep the last authoritative state — a
        // failed read never clears a pending request.
        debugPrint('Close-request read failed (line $lineId): ${e.code}');
      }
    } catch (e) {
      debugPrint('Close-request read failed (line $lineId): $e');
    }
  }

  void _applyFetchedCloseRequest(int lineId, PlanItemCloseRequest? fetched) {
    final previous = _closeRequests[lineId];
    // Only an ACTIVE request for THIS line is ever shown.
    final next =
        (fetched != null &&
            fetched.status.isActive &&
            fetched.palletizingLineId == lineId)
        ? fetched
        : null;

    if (previous != null &&
        (next == null || next.closeRequestId != previous.closeRequestId)) {
      _removeCloseRequest(lineId, notice: _vanishedNoticeKind(lineId));
    }
    if (next != null) {
      if (previous?.closeRequestId != next.closeRequestId ||
          previous?.status != next.status) {
        _closeDecisionErrors.remove(lineId);
      }
      _closeRequests[lineId] = next;
      _closeRequestSseHint.remove(lineId);
    }
    notifyListeners();
  }

  CloseRequestNoticeKind _vanishedNoticeKind(int lineId) {
    switch (_closeRequestSseHint[lineId]) {
      case _reasonCloseConfirmed:
        return CloseRequestNoticeKind.confirmed;
      case _reasonCloseCancelled:
        return CloseRequestNoticeKind.cancelled;
      default:
        return CloseRequestNoticeKind.noLongerValid;
    }
  }

  /// Removes the line's active request. The [notice] is queued only when a
  /// request was actually on screen, so one transition never notifies twice.
  void _removeCloseRequest(int lineId, {CloseRequestNoticeKind? notice}) {
    final removed = _closeRequests.remove(lineId);
    _closeDecisionErrors.remove(lineId);
    _closeRequestSseHint.remove(lineId);
    if (removed != null && notice != null) {
      _closeRequestNotices.add(
        CloseRequestNotice(lineId: lineId, kind: notice),
      );
    }
  }

  /// Session ended / line pruned: drop everything without a notice (the PIN
  /// screen or the line notice already explains it) and invalidate any read
  /// still in flight.
  void _clearCloseRequestState(int lineId) {
    _closeRequests.remove(lineId);
    _closeDecisionErrors.remove(lineId);
    _closeRequestSseHint.remove(lineId);
    _closeRequestForced.remove(lineId);
    _closeRequestFetchedAt.remove(lineId);
    _closeRequestSeq[lineId] = (_closeRequestSeq[lineId] ?? 0) + 1;
  }

  /// "لا، بقيت طبليات للتسجيل" for [closeRequestId] on [lineId].
  Future<CloseDecisionOutcome> reportMorePalletsRemain(
    int lineId,
    int closeRequestId,
  ) => _runCloseDecision(lineId, closeRequestId, confirm: false);

  /// "نعم، تم تسجيل جميع الطبليات" / "تأكيد وإنهاء البند" for
  /// [closeRequestId] on [lineId]. The backend closes the item and makes the
  /// next item current; the app only re-reads the line state afterwards.
  Future<CloseDecisionOutcome> confirmAllPalletsRegistered(
    int lineId,
    int closeRequestId,
  ) => _runCloseDecision(lineId, closeRequestId, confirm: true);

  Future<CloseDecisionOutcome> _runCloseDecision(
    int lineId,
    int closeRequestId, {
    required bool confirm,
  }) async {
    final active = _closeRequests[lineId];
    if (!isLineRendered(lineId) ||
        active == null ||
        active.closeRequestId != closeRequestId ||
        _closeDecisionInFlight.contains(lineId)) {
      return CloseDecisionOutcome.ignored;
    }
    // Claimed before the first await, so a double tap in the same frame can
    // never send a second request.
    _closeDecisionInFlight.add(lineId);
    _closeDecisionErrors.remove(lineId);
    notifyListeners();

    var outcome = CloseDecisionOutcome.failed;
    var itemClosed = false;
    try {
      final token = await _authStorage.getPalletizerSessionToken(lineId);
      if (token == null || token.isEmpty) {
        await _dropToStateB(lineId);
        return CloseDecisionOutcome.sessionLost;
      }

      PlanItemCloseRequest? result;
      Object? error;
      // One automatic retry for a transient failure: a retried decision is
      // safe (handoff §18 — `alreadyProcessed` on a replay).
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          result = confirm
              ? await _repository.confirmAllPalletsRegistered(
                  lineId: lineId,
                  closeRequestId: closeRequestId,
                  sessionToken: token,
                )
              : await _repository.reportMorePalletsRemain(
                  lineId: lineId,
                  closeRequestId: closeRequestId,
                  sessionToken: token,
                );
          error = null;
          break;
        } catch (e) {
          error = e;
          if (attempt > 0 || !_isTransientDecisionError(e)) break;
          await Future<void>.delayed(_closeDecisionRetryDelay);
          if (!isLineRendered(lineId)) break;
        }
      }

      if (!isLineRendered(lineId)) return outcome;
      if (result != null) {
        itemClosed = _applyDecisionResult(lineId, result);
        outcome = CloseDecisionOutcome.applied;
      } else {
        outcome = await _handleDecisionError(lineId, error);
      }
    } finally {
      _closeDecisionInFlight.remove(lineId);
    }

    // Handoff §6: re-read the pending request after every decision call;
    // after a close, the line's current product / plan item changed too.
    if (isLineRendered(lineId)) {
      await refreshCloseRequest(lineId);
      if (itemClosed) await _refreshLineStateFromBackend(lineId);
    }
    notifyListeners();
    return outcome;
  }

  static bool _isTransientDecisionError(Object e) =>
      e is ApiException &&
      (e.code == 'CONCURRENT_MODIFICATION' ||
          e.code == 'NETWORK_ERROR' ||
          e.code == 'TIMEOUT_ERROR');

  /// Applies a decision response. Returns `true` when the item was closed.
  bool _applyDecisionResult(int lineId, PlanItemCloseRequest result) {
    // Any read that started before this response is now stale.
    _closeRequestSeq[lineId] = (_closeRequestSeq[lineId] ?? 0) + 1;
    _closeRequestFetchedAt[lineId] = _clock();
    if (result.status.isActive && result.palletizingLineId == lineId) {
      _closeRequests[lineId] = result;
      _closeDecisionErrors.remove(lineId);
      _closeRequestSseHint.remove(lineId);
      return false;
    }
    final closed = result.status == PlanItemCloseRequestStatus.confirmed;
    _removeCloseRequest(
      lineId,
      notice: closed
          ? CloseRequestNoticeKind.confirmed
          : CloseRequestNoticeKind.noLongerValid,
    );
    return closed;
  }

  /// Maps a failed decision to the handoff §17 behaviour.
  Future<CloseDecisionOutcome> _handleDecisionError(
    int lineId,
    Object? error,
  ) async {
    if (error is! ApiException) {
      debugPrint('Close-request decision failed (line $lineId): $error');
      _closeDecisionErrors[lineId] = PlanItemCloseRequestStrings.genericFailure;
      return CloseDecisionOutcome.failed;
    }
    debugPrint(
      'Close-request decision failed (line $lineId): ${error.code} '
      '(status=${error.statusCode ?? "n/a"})',
    );
    switch (error.code) {
      case 'PALLETIZER_SESSION_REQUIRED':
        await _dropToStateB(lineId);
        return CloseDecisionOutcome.sessionLost;
      case 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_NOT_ACTIVE':
        // Confirmed elsewhere, cancelled or invalidated at the same moment.
        _removeCloseRequest(lineId, notice: _vanishedNoticeKind(lineId));
        return CloseDecisionOutcome.requestGone;
      case 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_STALE':
      case 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_NOT_FOUND':
        _removeCloseRequest(
          lineId,
          notice: CloseRequestNoticeKind.noLongerValid,
        );
        return CloseDecisionOutcome.requestGone;
      case 'PRODUCTION_LINE_INACTIVE':
      case 'PRODUCTION_LINE_NOT_FOUND':
        unawaited(refreshBootstrap());
        _closeDecisionErrors[lineId] = error.displayMessageForLine(
          lineLabel(lineId),
        );
        return CloseDecisionOutcome.failed;
      case 'THERMOFORMING_LINE_PAUSED':
        _closeDecisionErrors[lineId] = PlanItemCloseRequestStrings.linePaused;
        return CloseDecisionOutcome.failed;
      case 'CONCURRENT_MODIFICATION':
        _closeDecisionErrors[lineId] =
            PlanItemCloseRequestStrings.conflictRetry;
        return CloseDecisionOutcome.failed;
      default:
        // Network / timeout (after the retry) and every roll / plan rule the
        // close re-checks: nothing was closed, the request is still pending.
        _closeDecisionErrors[lineId] = error.displayMessage;
        return CloseDecisionOutcome.failed;
    }
  }

  // ── First-pallet context ──

  /// Called every time the user taps "إنشاء طبلية جديدة". The backend returns
  /// rich context telling us whether to open the include-FALET suggestion
  /// dialog. Throws ApiException on backend errors (notably 409
  /// `LINE_BLOCKED_BY_PENDING_HANDOVER`); callers must catch and react.
  Future<FirstPalletContext> fetchFirstPalletContext(int lineId) async {
    if (!isLineRendered(lineId)) {
      throw ApiException(
        code: 'PRODUCTION_LINE_INACTIVE',
        message: 'line $lineId is not rendered',
      );
    }

    _firstPalletContextLoading[lineId] = true;
    notifyListeners();

    try {
      final ctx = await _repository.getFirstPalletContext(lineId);
      // Keep the FALET indicator in sync with what the backend just returned
      // — the context is a more recent snapshot than the cached line state.
      if (isLineRendered(lineId)) _hasOpenFalet[lineId] = ctx.hasOpenFalet;
      return ctx;
    } on ApiException catch (e) {
      if (_isStaleLineError(e)) await refreshBootstrap();
      rethrow;
    } finally {
      if (isLineRendered(lineId)) _firstPalletContextLoading[lineId] = false;
      notifyListeners();
    }
  }

  // ── Create pallet (line-scoped) ──

  /// Creates a pallet on [lineId].
  ///
  /// [expectedPlanItemId] (V190, mandatory) is the line's `currentPlanItemId`
  /// captured together with [productTypeId] when the worker opened the
  /// create flow. A `PRODUCTION_PLAN_CURRENT_ITEM_CHANGED` rejection refreshes
  /// the line and is rethrown — it is never retried with a new id.
  ///
  /// [grindingRecommendationReason], when non-null, registers the pallet as
  /// recommended for grinding with that reason (validated by the caller).
  ///
  /// A line that is no longer rendered is rejected locally with
  /// `PRODUCTION_LINE_INACTIVE` (nothing is sent). A request already in flight
  /// when its line is removed still reports its own result.
  Future<PalletCreateResponse?> createPallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    required int expectedPlanItemId,
    bool confirmOverproduction = false,
    int? firstPalletFaletExpectedQuantity,
    int? firstPalletFaletId,
    String? grindingRecommendationReason,
  }) async {
    if (!isLineRendered(lineId)) {
      throw ApiException(
        code: 'PRODUCTION_LINE_INACTIVE',
        message: 'line $lineId is not rendered',
      );
    }

    _lineCreating[lineId] = true;
    _lineErrors[lineId] = null;
    notifyListeners();

    try {
      final response = await _repository.createLinePallet(
        lineId: lineId,
        productTypeId: productTypeId,
        quantity: quantity,
        expectedPlanItemId: expectedPlanItemId,
        confirmOverproduction: confirmOverproduction,
        firstPalletFaletExpectedQuantity: firstPalletFaletExpectedQuantity,
        firstPalletFaletId: firstPalletFaletId,
        grindingRecommendationReason: grindingRecommendationReason,
      );

      if (isLineRendered(lineId)) {
        _lastPalletResponses[lineId] = response;
        // The cached "selected product" tracks the plan-item product, not a
        // free operator choice. Refreshing line state below re-derives it
        // from the current plan item, so we don't override here from the
        // response.
        await _refreshLineStateFromBackend(lineId);
        _lineCreating.remove(lineId);
      }
      notifyListeners();
      return response;
    } on ApiException catch (e) {
      if (isLineRendered(lineId)) {
        _lineCreating.remove(lineId);
        _lineErrors[lineId] = e.displayMessageForLine(lineLabel(lineId));
      }
      notifyListeners();
      debugPrint(
        'PalletizingProvider createPallet API error: ${e.code} - ${e.message}',
      );
      // The action was rejected — the line may have moved on (handover /
      // takeover / block / operator change / plan item changed). Re-fetch the
      // authoritative state so the UI re-routes to the correct overlay
      // instead of leaving a stale screen behind a snackbar.
      //
      // PRODUCTION_PLAN_PRODUCT_MISMATCH / PRODUCTION_PLAN_CURRENT_ITEM_CHANGED
      // mean the cached plan item diverged; the refresh below pulls in the
      // fresh `currentPlanItemId` / product so the worker can check the
      // product before registering again. Never auto-retried.
      //
      // PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED must NOT trigger
      // a state refresh — the dialog flow re-sends the same request with
      // `confirmOverproduction: true`.
      if (_isStaleLineError(e)) {
        // Line switched off / removed — bootstrap drops the tab and the
        // screen shows the "تم إيقاف الخط" notice.
        await refreshBootstrap();
      } else if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        // Backend rejects pallet creation when no palletizer session exists.
        await _dropToStateB(lineId);
      } else if (e.code ==
          'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED') {
        // No-op — caller handles the confirmation dialog. Don't refresh and
        // don't clobber the in-flight request payload.
      } else {
        await _refreshLineStateFromBackend(lineId);
        notifyListeners();
      }
      rethrow;
    } catch (e) {
      if (isLineRendered(lineId)) {
        _lineCreating.remove(lineId);
        _lineErrors[lineId] = 'فشل في إنشاء الطبلية';
      }
      debugPrint('PalletizingProvider createPallet error: $e');
      notifyListeners();
      rethrow;
    }
  }

  // ── Print attempt logging (line-scoped) ──

  Future<bool> logPrintAttempt({
    required int lineId,
    required int palletId,
    required String printerIdentifier,
    required bool success,
    String? failureReason,
  }) async {
    // Not gated on the rendered list: a pallet created just before its line
    // was switched off is still printed; the backend's 400 is swallowed.
    try {
      await _repository.logLinePrintAttempt(
        lineId: lineId,
        palletId: palletId,
        printerIdentifier: printerIdentifier,
        status: success ? 'SUCCESS' : 'FAILED',
        failureReason: failureReason,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── Session production detail (drill-down) ──

  Future<SessionProductionDetail> fetchSessionProductionDetail(
    int lineId,
  ) async {
    return await _repository.getSessionProductionDetail(lineId);
  }

  // ── Pallet label reprint (unscoped — any shift / any line) ──

  /// Resolves any pallet by its 12-digit printed number and returns the label
  /// payload for reprinting. Not scoped to the current line, session, or shift.
  ///
  /// Throws [ApiException] with code `PALLET_LABEL_REPRINT_NOT_AVAILABLE`
  /// (409) when the pallet is cancelled, `PALLET_NOT_FOUND` (404) when no
  /// pallet carries that number.
  ///
  /// No provider-side state is mutated — a reprint never triggers a line-state,
  /// session-table, or SSE refresh.
  Future<PalletLabel> fetchPalletLabel(String scannedValue) {
    return _repository.fetchPalletLabel(scannedValue);
  }

  // ── FALET Items (unchanged surface) ──

  Future<void> fetchFaletItems(int lineId) async {
    if (!isLineRendered(lineId)) return;

    _faletItemsLoading[lineId] = true;
    notifyListeners();

    try {
      final result = await _repository.getFaletItems(lineId);
      if (!isLineRendered(lineId)) return;
      _faletItems[lineId] = result;
      _hasOpenFalet[lineId] = result.hasOpenFalet;
      _openFaletCount[lineId] = result.totalOpenFaletCount;
    } on ApiException catch (e) {
      _lineErrors[lineId] = e.displayMessage;
      debugPrint('fetchFaletItems error: ${e.code} - ${e.message}');
    } catch (e) {
      _lineErrors[lineId] = 'فشل في تحميل عناصر الفالت';
      debugPrint('fetchFaletItems unexpected error: $e');
    }

    if (isLineRendered(lineId)) _faletItemsLoading[lineId] = false;
    notifyListeners();
  }

  // ── FALET existence + line monitoring polling ──

  Future<void> checkFaletExists(int lineId) async {
    if (!isLineRendered(lineId)) return;

    try {
      final result = await _repository.checkFaletExists(lineId);
      if (!isLineRendered(lineId)) return;
      final changed =
          _hasOpenFalet[lineId] != result.hasOpenFalet ||
          _openFaletCount[lineId] != result.openFaletCount;
      if (changed) {
        _hasOpenFalet[lineId] = result.hasOpenFalet;
        _openFaletCount[lineId] = result.openFaletCount;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('checkFaletExists poll error (line $lineId): $e');
    }
  }

  /// Combined poll fired from the screen's self-rescheduling adaptive timer.
  /// The cadence ([nextPollInterval]) is recomputed after every round from the
  /// state this poll just wrote.
  ///
  /// A full `/state` refresh runs for **every rendered** line — no UI-state
  /// filter, and never for a line that is not in the last bootstrap. The Pallet Worker App is a passive observer whose
  /// only recovery from any stale state (waiting, blocked, pending-handover,
  /// takeover, or active) is a REST refresh, so a blocked / handover line
  /// that is not currently `authorized` must still be polled or it can never
  /// converge once the Thermoforming operator change commits. `/state` also
  /// carries the FALET counts, so this subsumes the old lightweight
  /// `checkFaletExists` poll branch.
  ///
  /// Tracks [lastPollFailed]: a round counts as failed only when **every**
  /// line failed — one line recovering proves the network is up.
  Future<void> pollLineMonitoring() async {
    final futures = <Future<bool>>[
      for (final lineId in _renderedLineIds)
        _refreshLineStateFromBackend(lineId),
    ];

    if (futures.isEmpty) return;
    final results = await Future.wait(futures);
    _lastPollFailed = results.every((ok) => !ok);
    notifyListeners();
  }

  /// One tick of the adaptive poll timer. Re-fetches bootstrap whenever at
  /// least the [PollCadence.safety] interval has passed since the last
  /// successful bootstrap (so a missed enable / disable frame is recovered),
  /// otherwise polls `/state` for the rendered lines.
  Future<void> onPollTick() async {
    final last = _lastBootstrapAt;
    if (last == null ||
        _clock().difference(last) >= PollCadence.safety.interval) {
      await refreshBootstrap();
      return;
    }
    await pollLineMonitoring();
  }

  // ── Error management ──

  void clearError() {
    _errorMessage = null;
    if (_state == PalletizingState.error) {
      _state = PalletizingState.loaded;
    }
    notifyListeners();
  }

  void clearLineError(int lineId) {
    _lineErrors[lineId] = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sseStateSub?.cancel();
    // Cancels the poll + debounce timers and stops + disposes the SseClient.
    _coordinator?.dispose();
    _notifications.dispose();
    super.dispose();
  }
}
