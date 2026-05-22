import 'dart:async';

import 'package:flutter/foundation.dart';

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
import '../../domain/entities/palletizer_session.dart';
import '../../domain/entities/palletizer_session_state.dart';
import '../../domain/entities/session_production_detail.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
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

  /// SSE is connected and nothing needs attention — a slow safety net behind
  /// the event stream.
  safety(Duration(seconds: 50));

  const PollCadence(this.interval);
  final Duration interval;
}

class PalletizingProvider extends ChangeNotifier {
  final PalletizingRepository _repository;
  final AuthLocalStorage _authStorage;
  final TakeoverNotificationService _notifications;

  /// Owns the poll timer + SSE bridge. `null` in unit tests that construct the
  /// provider without an [SseClient] — the provider then behaves as a pure
  /// REST poller (plus the session-endpoint gate).
  RefreshCoordinator? _coordinator;
  StreamSubscription<SseConnectionState>? _sseStateSub;

  PalletizingProvider(
    this._repository,
    this._authStorage,
    this._notifications, {
    SseClient? sseClient,
  }) {
    if (sseClient != null) {
      _coordinator = RefreshCoordinator(
        sseClient: sseClient,
        onPoll: pollLineMonitoring,
        onEventRefresh: refreshFromSseEvent,
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

  // ── Reference data ──
  List<ProductType> _productTypes = [];
  List<ProductionLine> _productionLines = [];

  // ── Per-line state (keyed by UI lineNumber: 1, 2) ──
  // Backend lineId is resolved via getLineIdForNumber before any storage / API.
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

  // ── Adaptive polling ──
  /// `true` when the most recent [pollLineMonitoring] round failed for every
  /// line (network/timeout). Drives the [PollCadence.retry] back-off.
  bool _lastPollFailed = false;

  /// Monotonic per-line counter for `/state` refreshes. Each refresh captures
  /// the counter before its REST call; on completion it applies the response
  /// only if no newer refresh for the same line started since. This drops an
  /// out-of-order (slow, overtaken) `/state` response so it can never overwrite
  /// fresher state. See the SSE handoff §6 (out-of-order REST responses).
  final Map<int, int> _lineStateSeq = {};

  /// Latest device-level SSE connection state. Drives the cadence split
  /// between [PollCadence.safety] (connected) and [PollCadence.fallback].
  SseConnectionState _sseState = SseConnectionState.disconnected;

  // ── Palletizer-session gate ──
  /// Per-line cache (keyed by UI lineNumber) of whether the app has any local
  /// signal that a palletizer session may exist — a stored session token. When
  /// `false`, `/palletizer-session/current` is NEVER called, which is what
  /// stops the `PALLETIZER_SESSION_REQUIRED` log spam. Primed from secure
  /// storage on bootstrap; set `true` on successful auth, `false` on drop.
  final Map<int, bool> _maybeHasPalletizerSession = {};

  // ── Global getters ──
  PalletizingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == PalletizingState.loading;
  List<ProductType> get productTypes => _productTypes;
  List<ProductionLine> get productionLines => _productionLines;

  bool get isCreating => _lineCreating.values.any((v) => v);

  // ── Per-line getters ──

  bool isLineAuthorized(int lineNumber) =>
      _lineStates[lineNumber]?.isAuthorized ?? false;

  Operator? getAuthorizedOperator(int lineNumber) =>
      _lineStates[lineNumber]?.authorizedOperator;

  PalletizerSessionState? getPalletizerSessionState(int lineNumber) =>
      _palletizerSessions[lineNumber];

  PalletizerSession? getPalletizerSession(int lineNumber) =>
      _palletizerSessions[lineNumber]?.session;

  bool isPalletizerAuthenticating(int lineNumber) =>
      _palletizerSessions[lineNumber]?.isAuthenticating ?? false;

  String? getPalletizerName(int lineNumber) =>
      _palletizerSessions[lineNumber]?.session?.palletizerName;

  String? getPalletizerAuthError(int lineNumber) =>
      _palletizerSessions[lineNumber]?.authError;

  String? getPalletizerAuthErrorCode(int lineNumber) =>
      _palletizerSessions[lineNumber]?.authErrorCode;

  bool hasActivePalletizerSession(int lineNumber) =>
      _palletizerSessions[lineNumber]?.hasActiveSession ?? false;

  List<SessionTableRow> getSessionTable(int lineNumber) =>
      _sessionTables[lineNumber] ?? [];

  /// The current Thermoforming Production Plan item product, hydrated by
  /// [_resolveProductType] strictly from the plan-item fields on the line
  /// state. Returns `null` when there is no active plan item — the UI must
  /// render a no-plan blocked state in that case, never an old product.
  ProductType? getCurrentPlanItemProductType(int lineNumber) =>
      _planItemProducts[lineNumber];

  /// Product type id of the current Thermoforming Production Plan item; the
  /// ONLY id the Palletizing App is allowed to send in a create-pallet
  /// request. `null` means the line has no active plan item, and create-pallet
  /// must be disabled.
  int? getCurrentPlanItemProductTypeId(int lineNumber) =>
      _lineStates[lineNumber]?.currentPlanItemProductTypeId;

  /// Display name from the current Thermoforming Production Plan item.
  String? getCurrentPlanItemProductName(int lineNumber) =>
      _lineStates[lineNumber]?.currentPlanItemProductName;

  /// `true` when the backend reports the line is blocked specifically by
  /// production-plan state (no plan item / paused / target rules). V81
  /// classifies this as a defensive fallback — under the normal flow the line
  /// also has no active operator and the waiting-for-operator overlay covers
  /// the UI — but the create-pallet button must still react to it.
  bool isProductionPlanBlocked(int lineNumber) =>
      _lineStates[lineNumber]?.productionPlanBlocked ?? false;

  /// Localized message backing [isProductionPlanBlocked]. Returns the backend
  /// `productionPlanBlockedMessage` when present, otherwise a safe Arabic
  /// fallback so the UI never shows an empty block.
  String? getProductionPlanBlockedMessage(int lineNumber) {
    final s = _lineStates[lineNumber];
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
  int? getCurrentPlanItemPackagesPerPallet(int lineNumber) =>
      _lineStates[lineNumber]?.currentPlanItemPackagesPerPallet;

  /// `"PLAN_ITEM"` / `"PRODUCT_TYPE"` — which source the backend default came
  /// from. Drives whether the UI may fall back to ProductType.packageQuantity.
  String? getDefaultPackageQuantitySource(int lineNumber) =>
      _lineStates[lineNumber]?.defaultPackageQuantitySource;

  /// Backend-authoritative (V81+, 2026-05-21): `true` when the line is
  /// thermoforming-linked but has no active operator session. Drives the
  /// [ThermoformingWaitingCard] overlay via [getUiState].
  bool isWaitingForOperator(int lineNumber) =>
      _lineStates[lineNumber]?.waitingForOperator ?? false;

  /// Localized title from `LineStateResponse.waitingForOperatorMessageTitle`,
  /// or `null` when not provided (or whitespace-only) — in which case
  /// [ThermoformingWaitingCard] uses its hardcoded Arabic fallback.
  String? getWaitingForOperatorTitle(int lineNumber) {
    final s = _lineStates[lineNumber]?.waitingForOperatorMessageTitle;
    return (s != null && s.trim().isNotEmpty) ? s : null;
  }

  /// Localized body from `LineStateResponse.waitingForOperatorMessage`,
  /// or `null` when not provided (or whitespace-only) — in which case
  /// [ThermoformingWaitingCard] uses its hardcoded Arabic fallback.
  String? getWaitingForOperatorMessage(int lineNumber) {
    final s = _lineStates[lineNumber]?.waitingForOperatorMessage;
    return (s != null && s.trim().isNotEmpty) ? s : null;
  }

  PalletCreateResponse? getLastPalletResponse(int lineNumber) =>
      _lastPalletResponses[lineNumber];

  String? getBlockedReason(int lineNumber) => _blockedReasons[lineNumber];

  bool isLineCreating(int lineNumber) => _lineCreating[lineNumber] ?? false;

  String? getLineError(int lineNumber) => _lineErrors[lineNumber];

  String? getLineUiMode(int lineNumber) => _lineUiModes[lineNumber];

  FaletResponse? getFaletItems(int lineNumber) => _faletItems[lineNumber];

  bool isFaletItemsLoading(int lineNumber) =>
      _faletItemsLoading[lineNumber] ?? false;

  bool hasOpenFalet(int lineNumber) => _hasOpenFalet[lineNumber] ?? false;

  int getOpenFaletCount(int lineNumber) => _openFaletCount[lineNumber] ?? 0;

  bool isFirstPalletContextLoading(int lineNumber) =>
      _firstPalletContextLoading[lineNumber] ?? false;

  // ── Takeover getters ──

  /// Current takeover request for the line, or `null` when there is none.
  TakeoverRequest? getTakeover(int lineNumber) => _takeovers[lineNumber];

  /// True while a takeover is PENDING or ACCEPTED (still live).
  bool hasActiveTakeover(int lineNumber) =>
      _takeovers[lineNumber]?.status.isActive ?? false;

  /// True whenever the line has any takeover state that should keep the poll
  /// on its fast cadence and a banner on screen.
  bool hasAnyTakeoverActivity(int lineNumber) =>
      _takeovers[lineNumber] != null;

  /// True when the screen still needs to show the blocking takeover dialog
  /// for this line (not yet acknowledged).
  bool isTakeoverDialogPending(int lineNumber) =>
      _pendingDialogLines.contains(lineNumber);

  /// Pallet creation must be blocked. Combines the existing line-UI blocks
  /// with takeover-specific blocking. Kept SEPARATE from [getUiState] so a
  /// takeover never renders as the legacy-handover overlay.
  ///
  /// PENDING / ACCEPTED do **not** block on their own — only the backend
  /// `blocked` flag or an auto-released line does.
  bool isPalletCreationBlocked(int lineNumber) {
    if (isLineBlocked(lineNumber)) return true;
    if (_lineBlockedFlag[lineNumber] == true) return true;
    final t = _takeovers[lineNumber];
    if (t != null && t.status.isAutoReleased) return true;
    return false;
  }

  bool isLineBlocked(int lineNumber) {
    final ui = getUiState(lineNumber);
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
  LineUiState getUiState(int lineNumber) {
    // 1. Pending legacy handover — a dedicated flow with its own overlay. It
    //    must win even over "no operator": during a handover the line is
    //    transiently unauthorized by design.
    final mode = _lineUiModes[lineNumber];
    if (mode == 'PENDING_HANDOVER_NEEDS_INCOMING') {
      return LineUiState.pendingHandoverIncoming;
    }
    if (mode == 'PENDING_HANDOVER_REVIEW') {
      return LineUiState.pendingHandoverReview;
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
    final lineState = _lineStates[lineNumber];
    if (lineState == null ||
        lineState.waitingForOperator ||
        !lineState.isAuthorized ||
        lineState.authorizedOperator == null) {
      return LineUiState.waitingForThermoforming;
    }

    // 3. Backend-authoritative block for a line that DOES have an operator
    //    (equipment fault, admin block, …) — kept distinct so a real block is
    //    never silently relabelled as "no operator".
    if ((_blockedReasons[lineNumber] ?? '').isNotEmpty) {
      return LineUiState.blocked;
    }

    // 4. Authorized + operator present.
    if (!hasActivePalletizerSession(lineNumber)) {
      return LineUiState.needsPalletizerAuth;
    }
    return LineUiState.active;
  }

  int? getLineIdForNumber(int lineNumber) {
    final fromList = _productionLines
        .where((l) => l.lineNumber == lineNumber)
        .firstOrNull;
    return fromList?.id ?? _lineStates[lineNumber]?.lineId;
  }

  // ── Adaptive polling ──

  /// `true` when the most recent poll round failed for every line.
  bool get lastPollFailed => _lastPollFailed;

  /// Union of every line number known from bootstrap reference data or any
  /// cached line state.
  Iterable<int> get _allLineNumbers => <int>{
    ..._lineStates.keys,
    ..._productionLines.map((l) => l.lineNumber),
  };

  /// `true` when [lineNumber] is in a state that demands fast polling: blocked
  /// by the backend, mid legacy-handover, mid-takeover (including the
  /// auto-released terminal states), or waiting for the Thermoforming operator
  /// (no active operator). Steady `active` and `needsPalletizerAuth` lines are
  /// NOT urgent.
  ///
  /// Exposed as a simple boolean so the screen never has to reason about the
  /// individual backend fields.
  bool hasUrgentLineState(int lineNumber) {
    // Backend-authoritative blocked flag / reason.
    if (_lineBlockedFlag[lineNumber] == true) return true;
    if ((_blockedReasons[lineNumber] ?? '').isNotEmpty) return true;

    // Pending legacy handover.
    final mode = _lineUiModes[lineNumber];
    if (mode == 'PENDING_HANDOVER_NEEDS_INCOMING' ||
        mode == 'PENDING_HANDOVER_REVIEW') {
      return true;
    }

    // Any takeover request — pending, accepted, or auto-released — keeps the
    // poll fast so the banner / dialog / countdown stay responsive. This
    // mirrors `pendingTakeoverRequest != null` / `takeoverRequestStatus`.
    if (_takeovers[lineNumber] != null) return true;

    // Waiting for the Thermoforming operator (no active operator) or a
    // blocked / handover UI branch.
    switch (getUiState(lineNumber)) {
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

  /// `true` when any known line is urgent — drives [PollCadence.urgent].
  bool get hasAnyUrgentLineState => _allLineNumbers.any(hasUrgentLineState);

  /// Cadence bucket for the next poll. Urgent always wins; a fully failed
  /// round backs off to [PollCadence.retry]; while SSE is down the
  /// [PollCadence.fallback] cadence is the only refresh channel; with SSE
  /// connected and steady, [PollCadence.safety] is just a slow safety net.
  PollCadence get pollCadence {
    if (hasAnyUrgentLineState) return PollCadence.urgent;
    if (_lastPollFailed) return PollCadence.retry;
    if (_sseState != SseConnectionState.connected) return PollCadence.fallback;
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

  /// Refreshes authoritative REST state after a debounced SSE event. A
  /// resolvable line id refreshes just that line; otherwise every line's
  /// `/state` is refreshed. Never calls `loadBootstrap` — an SSE refresh must
  /// not flash the loading shimmer.
  Future<void> refreshFromSseEvent(int? palletizingLineId) async {
    if (palletizingLineId != null) {
      final lineNumber = _lineNumberForLineId(palletizingLineId);
      if (lineNumber != null) {
        await refreshLineState(lineNumber);
        return;
      }
    }
    await pollLineMonitoring();
  }

  /// Inverse of [getLineIdForNumber]: resolves a backend lineId to the UI
  /// lineNumber, or `null` when the line is unknown.
  int? _lineNumberForLineId(int lineId) {
    final fromList = _productionLines
        .where((l) => l.id == lineId)
        .firstOrNull;
    if (fromList != null) return fromList.lineNumber;
    for (final entry in _lineStates.entries) {
      if (entry.value.lineId == lineId) return entry.key;
    }
    return null;
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

  Future<void> loadBootstrap() async {
    _state = PalletizingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final bootstrap = await _repository.bootstrap();

      _productTypes = bootstrap.productTypes;
      _productionLines = bootstrap.productionLines;

      for (final lineState in bootstrap.lines) {
        _hydrateLineState(lineState.lineNumber, lineState);
      }

      // Prime the session-token gate before any session refresh so a cold
      // start with no stored token makes zero `/palletizer-session/current`
      // calls.
      await _primeSessionTokenCache();

      // For every authorized line, sync the palletizer session from the
      // backend + secure storage so cold start lands directly in State C
      // when a session is still alive. Each call is internally gated by
      // [_mayHavePalletizerSession] — lines with no stored token are skipped.
      await Future.wait(
        bootstrap.lines
            .where((l) => l.isAuthorized)
            .map((l) => refreshPalletizerSession(l.lineNumber)),
      );

      _state = PalletizingState.loaded;
      // A successful bootstrap is also a successful round trip — clear any
      // earlier network-failure back-off.
      _lastPollFailed = false;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _state = PalletizingState.error;
      _lastPollFailed = true;
      debugPrint(
        'PalletizingProvider bootstrap error: ${e.code} - ${e.message}',
      );
    } catch (e, stackTrace) {
      _errorMessage = 'فشل في تحميل البيانات: $e';
      _state = PalletizingState.error;
      _lastPollFailed = true;
      debugPrint('PalletizingProvider bootstrap unexpected error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    notifyListeners();
  }

  // ── Refresh single line state ──

  Future<void> refreshLineState(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;
    await _refreshLineStateFromBackend(lineNumber, lineId);
    notifyListeners();
  }

  /// Refreshes one line from `/state`. Returns `true` when the backend call
  /// succeeded and `false` on any network / timeout / API failure —
  /// [pollLineMonitoring] aggregates this into the retry cadence.
  ///
  /// Overlapping refreshes for the same line (an SSE-driven refresh racing a
  /// safety poll, say) are made order-safe by [_lineStateSeq]: a response that
  /// has been overtaken by a newer refresh is dropped rather than applied, so a
  /// slow out-of-order `/state` response can never overwrite fresher state. A
  /// dropped response still counts as success — the network round-trip worked.
  Future<bool> _refreshLineStateFromBackend(int lineNumber, int lineId) async {
    final seq = (_lineStateSeq[lineNumber] ?? 0) + 1;
    _lineStateSeq[lineNumber] = seq;
    try {
      final lineState = await _repository.getLineState(lineId);

      // A newer refresh for this line started while this call was in flight —
      // its fresher response wins, so drop this now-stale one untouched.
      if (_lineStateSeq[lineNumber] != seq) return true;

      _hydrateLineState(lineNumber, lineState);

      // Re-sync the palletizer session whenever line state changes so we drop
      // back to State B if the backend ended the session (e.g. shift-line ended).
      if (lineState.isAuthorized) {
        await refreshPalletizerSession(lineNumber);
      } else {
        // Line was de-authorized — the bound palletizer session is gone too.
        await _dropToStateB(lineNumber);
      }
      return true;
    } catch (e) {
      debugPrint('Failed to refresh line $lineNumber state: $e');
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
    final match = _productTypes
        .where((p) => p.id == planProductId)
        .firstOrNull;
    if (match != null) return match;

    // Catalog miss (rare — admin can add a product mid-shift). Fall back to a
    // minimal product type built from the plan-item fields on the line state
    // so the UI still shows the plan-item name.
    if (planProductName != null && planProductName.isNotEmpty) {
      return ProductType(
        id: planProductId,
        name: planProductName,
        productName: planProductName,
        prefix: '',
        color: '',
        packageQuantity: lineState.currentPlanItemPackagesPerPallet ?? 0,
        packageUnit: '',
        packageUnitDisplayName: '',
      );
    }
    return null;
  }

  void _hydrateLineState(int lineNumber, BootstrapLineState lineState) {
    _lineStates[lineNumber] = lineState;
    _sessionTables[lineNumber] = lineState.sessionTable;
    _blockedReasons[lineNumber] = lineState.blockedReason;
    _lineUiModes[lineNumber] = lineState.lineUiMode;
    _hasOpenFalet[lineNumber] = lineState.hasOpenFalet;
    _openFaletCount[lineNumber] = lineState.openFaletCount;
    _planItemProducts[lineNumber] = _resolveProductType(lineState);
    _palletizerSessions[lineNumber] ??= PalletizerSessionState.empty(
      lineNumber,
    );
    _lineBlockedFlag[lineNumber] = lineState.blocked;
    _applyTakeoverState(lineNumber, lineState.pendingTakeoverRequest);

    // ── Temporary diagnostic (debug builds only) ──────────────────────────
    // Logs the raw backend fields that drive [getUiState] every time a line
    // is hydrated (bootstrap + each poll). Use this to confirm on-device why
    // a line routes to a given LineUiState — e.g. a no-operator line that
    // also carries a `blockedReason`. Safe to delete once verified; compiled
    // out of release builds by `kDebugMode`.
    if (kDebugMode) {
      debugPrint(
        '[LineUiState] line=$lineNumber '
        'isAuthorized=${lineState.isAuthorized} '
        'authorizedOperator=${lineState.authorizedOperator?.displayLabel ?? 'null'} '
        'waitingForOperator=${lineState.waitingForOperator} '
        'blockedReason=${lineState.blockedReason ?? 'null'} '
        'lineUiMode=${lineState.lineUiMode ?? 'null'} '
        'blocked=${lineState.blocked} '
        '=> ${getUiState(lineNumber)}',
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
  void _applyTakeoverState(int lineNumber, TakeoverRequest? incoming) {
    _takeovers[lineNumber] = incoming;
    if (incoming == null) {
      _pendingDialogLines.remove(lineNumber);
      return;
    }

    if (incoming.status.isActive &&
        !_alertedTakeoverIds.contains(incoming.id)) {
      _alertedTakeoverIds.add(incoming.id);
      // Fire-and-forget — failures are swallowed inside the service.
      _notifications.alert();
      if (!_acknowledgedTakeoverIds.contains(incoming.id)) {
        _pendingDialogLines.add(lineNumber);
      }
    }
  }

  /// Called when the worker taps "حسناً" on the blocking takeover dialog.
  /// Records the request id as acknowledged so a late poll cannot re-pop the
  /// dialog, then collapses it into the persistent banner.
  void acknowledgeTakeover(int lineNumber) {
    final t = _takeovers[lineNumber];
    if (t != null) _acknowledgedTakeoverIds.add(t.id);
    _pendingDialogLines.remove(lineNumber);
    notifyListeners();
  }

  /// Called by the screen right before it shows the dialog, so the same
  /// signal is not consumed twice while the dialog is open.
  void consumeTakeoverDialogSignal(int lineNumber) {
    _pendingDialogLines.remove(lineNumber);
  }

  // ── Palletizer auth ──

  Future<bool> palletizerAuth(int lineNumber, String pin) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

    _palletizerSessions[lineNumber] =
        (_palletizerSessions[lineNumber] ??
                PalletizerSessionState.empty(lineNumber))
            .copyWith(isAuthenticating: true, clearAuthError: true);
    notifyListeners();

    try {
      final result = await _repository.palletizerAuth(lineId: lineId, pin: pin);

      // Persist the raw token ONCE — namespaced by backend lineId.
      await _authStorage.savePalletizerSessionToken(
        lineId,
        result.sessionToken,
      );
      // The app now has a session — re-open the `/palletizer-session/current`
      // gate for this line.
      _maybeHasPalletizerSession[lineNumber] = true;

      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        session: result.session,
      );

      // Refresh line state to pick up any backend-side changes (operator name,
      // handover transitions, etc.) — but don't let it stomp the session we
      // just stored.
      try {
        final lineState = await _repository.getLineState(lineId);
        _hydrateLineState(lineNumber, lineState);
      } catch (e) {
        debugPrint('Post-auth line refresh error (line $lineNumber): $e');
      }

      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        isAuthenticating: false,
        authError: e.displayMessage,
        authErrorCode: e.code,
      );
      notifyListeners();
      return false;
    } catch (e) {
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
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
  bool _mayHavePalletizerSession(int lineNumber) {
    if (_palletizerSessions[lineNumber]?.hasActiveSession ?? false) return true;
    return _maybeHasPalletizerSession[lineNumber] ?? false;
  }

  /// Primes [_maybeHasPalletizerSession] from secure storage once per known
  /// line, so the per-poll gate never has to await secure storage.
  Future<void> _primeSessionTokenCache() async {
    for (final lineNumber in _allLineNumbers) {
      final lineId = getLineIdForNumber(lineNumber);
      if (lineId == null) continue;
      final token = await _authStorage.getPalletizerSessionToken(lineId);
      _maybeHasPalletizerSession[lineNumber] =
          token != null && token.isNotEmpty;
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
  Future<void> refreshPalletizerSession(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    if (!_mayHavePalletizerSession(lineNumber)) return;

    try {
      final session = await _repository.getCurrentPalletizerSession(lineId);
      _palletizerSessions[lineNumber] = PalletizerSessionState(
        lineNumber: lineNumber,
        session: session,
      );
      notifyListeners();
    } on ApiException catch (e) {
      if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        await _dropToStateB(lineNumber);
      } else {
        debugPrint(
          'refreshPalletizerSession error (line $lineNumber): ${e.code} - ${e.message}',
        );
      }
    } catch (e) {
      debugPrint(
        'refreshPalletizerSession unexpected error (line $lineNumber): $e',
      );
    }
  }

  Future<void> palletizerLogout(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    final token = await _authStorage.getPalletizerSessionToken(lineId);
    if (token != null && token.isNotEmpty) {
      try {
        await _repository.palletizerLogout(lineId: lineId, sessionToken: token);
      } on ApiException catch (e) {
        // Idempotent — any flavor of session-required is treated as success.
        if (e.code != 'PALLETIZER_SESSION_REQUIRED') {
          debugPrint(
            'palletizerLogout error (line $lineNumber): ${e.code} - ${e.message}',
          );
        }
      } catch (e) {
        debugPrint('palletizerLogout unexpected error (line $lineNumber): $e');
      }
    }

    await _dropToStateB(lineNumber);
    // Logout — drop transient polling/error bookkeeping so the next session
    // starts clean (the screen cancels its poll timer separately).
    clearTransientRefreshState();
  }

  /// Clears the local session + secure-storage token and notifies listeners.
  /// Used by logout, by PALLETIZER_SESSION_REQUIRED interception, and by line
  /// de-authorization (operator ended the shift-line).
  Future<void> _dropToStateB(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId != null) {
      await _authStorage.clearPalletizerSessionToken(lineId);
    }
    // No token, no session — close the `/palletizer-session/current` gate so
    // a 404 is never retried in a loop until the next successful auth.
    _maybeHasPalletizerSession[lineNumber] = false;
    _palletizerSessions[lineNumber] = PalletizerSessionState.empty(lineNumber);
    notifyListeners();
  }

  void clearPalletizerAuthError(int lineNumber) {
    final current = _palletizerSessions[lineNumber];
    if (current != null && current.authError != null) {
      _palletizerSessions[lineNumber] = current.copyWith(clearAuthError: true);
      notifyListeners();
    }
  }

  // ── First-pallet context ──

  /// Called every time the user taps "إنشاء طبلية جديدة". The backend returns
  /// rich context telling us whether to open the include-FALET suggestion
  /// dialog. Throws ApiException on backend errors (notably 409
  /// `LINE_BLOCKED_BY_PENDING_HANDOVER`); callers must catch and react.
  Future<FirstPalletContext> fetchFirstPalletContext(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) {
      throw StateError('No lineId found for lineNumber $lineNumber');
    }

    _firstPalletContextLoading[lineNumber] = true;
    notifyListeners();

    try {
      final ctx = await _repository.getFirstPalletContext(lineId);
      // Keep the FALET indicator in sync with what the backend just returned
      // — the context is a more recent snapshot than the cached line state.
      _hasOpenFalet[lineNumber] = ctx.hasOpenFalet;
      return ctx;
    } finally {
      _firstPalletContextLoading[lineNumber] = false;
      notifyListeners();
    }
  }

  // ── Create pallet (line-scoped) ──

  Future<PalletCreateResponse?> createPallet({
    required int lineNumber,
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return null;

    _lineCreating[lineNumber] = true;
    _lineErrors[lineNumber] = null;
    notifyListeners();

    try {
      final response = await _repository.createLinePallet(
        lineId: lineId,
        productTypeId: productTypeId,
        quantity: quantity,
        confirmOverproduction: confirmOverproduction,
      );

      _lastPalletResponses[lineNumber] = response;
      // The cached "selected product" tracks the plan-item product, not a
      // free operator choice. Refreshing line state below re-derives it from
      // the current plan item, so we don't override here from the response.

      await _refreshLineStateFromBackend(lineNumber, lineId);

      _lineCreating[lineNumber] = false;
      notifyListeners();
      return response;
    } on ApiException catch (e) {
      _lineCreating[lineNumber] = false;
      _lineErrors[lineNumber] = e.displayMessage;
      notifyListeners();
      debugPrint(
        'PalletizingProvider createPallet API error: ${e.code} - ${e.message}',
      );
      // The action was rejected — the line may have moved on (handover /
      // takeover / block / operator change / plan item changed). Re-fetch the
      // authoritative state so the UI re-routes to the correct overlay
      // instead of leaving a stale screen behind a snackbar.
      //
      // PRODUCTION_PLAN_PRODUCT_MISMATCH specifically means the cached
      // product diverged from the current plan item; the refresh below pulls
      // in the fresh `currentPlanItemProductTypeId` / `..ProductName` so the
      // next attempt sends the correct id.
      //
      // PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED must NOT trigger
      // a state refresh — the dialog flow re-sends the same request with
      // `confirmOverproduction: true`.
      if (e.code == 'PALLETIZER_SESSION_REQUIRED') {
        // Backend rejects pallet creation when no palletizer session exists.
        await _dropToStateB(lineNumber);
      } else if (e.code ==
          'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED') {
        // No-op — caller handles the confirmation dialog. Don't refresh and
        // don't clobber the in-flight request payload.
      } else {
        await _refreshLineStateFromBackend(lineNumber, lineId);
        notifyListeners();
      }
      rethrow;
    } catch (e) {
      _lineCreating[lineNumber] = false;
      _lineErrors[lineNumber] = 'فشل في إنشاء الطبلية';
      debugPrint('PalletizingProvider createPallet error: $e');
      notifyListeners();
      rethrow;
    }
  }

  // ── Print attempt logging (line-scoped) ──

  Future<bool> logPrintAttempt({
    required int lineNumber,
    required int palletId,
    required String printerIdentifier,
    required bool success,
    String? failureReason,
  }) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return false;

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
    int lineNumber,
  ) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) {
      throw StateError('No lineId found for lineNumber $lineNumber');
    }
    return await _repository.getSessionProductionDetail(lineId);
  }

  // ── FALET Items (unchanged surface) ──

  Future<void> fetchFaletItems(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    _faletItemsLoading[lineNumber] = true;
    notifyListeners();

    try {
      final result = await _repository.getFaletItems(lineId);
      _faletItems[lineNumber] = result;
      _hasOpenFalet[lineNumber] = result.hasOpenFalet;
      _openFaletCount[lineNumber] = result.totalOpenFaletCount;
    } on ApiException catch (e) {
      _lineErrors[lineNumber] = e.displayMessage;
      debugPrint('fetchFaletItems error: ${e.code} - ${e.message}');
    } catch (e) {
      _lineErrors[lineNumber] = 'فشل في تحميل عناصر الفالت';
      debugPrint('fetchFaletItems unexpected error: $e');
    }

    _faletItemsLoading[lineNumber] = false;
    notifyListeners();
  }

  // ── FALET existence + line monitoring polling ──

  Future<void> checkFaletExists(int lineNumber) async {
    final lineId = getLineIdForNumber(lineNumber);
    if (lineId == null) return;

    try {
      final result = await _repository.checkFaletExists(lineId);
      final changed =
          _hasOpenFalet[lineNumber] != result.hasOpenFalet ||
          _openFaletCount[lineNumber] != result.openFaletCount;
      if (changed) {
        _hasOpenFalet[lineNumber] = result.hasOpenFalet;
        _openFaletCount[lineNumber] = result.openFaletCount;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('checkFaletExists poll error (line $lineNumber): $e');
    }
  }

  /// Combined poll fired from the screen's self-rescheduling adaptive timer.
  /// The cadence ([nextPollInterval]) is recomputed after every round from the
  /// state this poll just wrote.
  ///
  /// A full `/state` refresh runs for **every** line with a resolvable id —
  /// no UI-state filter. The Pallet Worker App is a passive observer whose
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
    final futures = <Future<bool>>[];

    for (final lineNumber in _allLineNumbers) {
      final lineId = getLineIdForNumber(lineNumber);
      if (lineId == null) continue;
      futures.add(_refreshLineStateFromBackend(lineNumber, lineId));
    }

    if (futures.isEmpty) return;
    final results = await Future.wait(futures);
    _lastPollFailed = results.every((ok) => !ok);
    notifyListeners();
  }

  // ── Error management ──

  void clearError() {
    _errorMessage = null;
    if (_state == PalletizingState.error) {
      _state = PalletizingState.loaded;
    }
    notifyListeners();
  }

  void clearLineError(int lineNumber) {
    _lineErrors[lineNumber] = null;
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
