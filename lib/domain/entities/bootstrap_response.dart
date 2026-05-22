import 'operator.dart';
import 'product_type.dart';
import 'production_line.dart';
import 'session_table_row.dart';
import 'takeover_request.dart';

class BootstrapResponse {
  final List<ProductType> productTypes;
  final List<ProductionLine> productionLines;
  final List<BootstrapLineState> lines;

  const BootstrapResponse({
    required this.productTypes,
    required this.productionLines,
    required this.lines,
  });
}

class BootstrapLineState {
  final int lineId;
  final int lineNumber;
  final String lineName;
  final bool isAuthorized;
  final Operator? authorizedOperator;
  final DateTime? authorizedAt;
  final List<SessionTableRow> sessionTable;
  final String? blockedReason;

  final String? lineUiMode;
  final bool hasOpenFalet;
  final int openFaletCount;

  // ── Thermoforming Production Plan (V79/V81) — authoritative product ──
  /// Id of the current Thermoforming Production Plan item; `null` when none.
  final int? currentPlanItemId;

  /// Product type id taken from the current plan item. The only id the
  /// Palletizing App may send when creating a pallet.
  final int? currentPlanItemProductTypeId;

  /// Display name for the current plan-item product. The only product label
  /// the Palletizing App may show.
  final String? currentPlanItemProductName;

  /// packages-per-pallet of the current production-plan item for this line.
  /// `null` when there is no active plan / no current item.
  final int? currentPlanItemPackagesPerPallet;

  /// `"PLAN_ITEM"` or `"PRODUCT_TYPE"` — which source the backend default came
  /// from. Under the enforced plan flow this should always be `PLAN_ITEM`.
  final String? defaultPackageQuantitySource;

  /// `true` when the line is blocked specifically by production-plan state —
  /// e.g. no active plan item, plan paused, target exceeded without override.
  /// Distinct from the generic `blocked` flag.
  final bool productionPlanBlocked;

  /// Machine-readable reason for [productionPlanBlocked]
  /// (e.g. `PRODUCTION_PLAN_ITEM_REQUIRED`).
  final String? productionPlanBlockedReason;

  /// Localized message backing [productionPlanBlocked] — used directly in the
  /// UI block surfaces when present.
  final String? productionPlanBlockedMessage;

  // ── Waiting-for-Operator (V81+, 2026-05-21) ──
  /// Backend-authoritative: `true` when this thermoforming-linked line has no
  /// active operator session. Drives the [ThermoformingWaitingCard] overlay.
  /// Always `false` for non-thermoforming-linked lines.
  final bool waitingForOperator;

  /// Machine-readable reason; currently always
  /// `"NO_ACTIVE_THERMOFORMING_OPERATOR"` when set.
  final String? waitingForOperatorReason;

  /// Localized title for the waiting overlay (e.g. "بانتظار استلام الخط").
  /// UI must render verbatim when non-empty.
  final String? waitingForOperatorMessageTitle;

  /// Localized body for the waiting overlay. UI must render verbatim when
  /// non-empty; fall back to the hardcoded Arabic body otherwise.
  final String? waitingForOperatorMessage;

  // ── Line Takeover Request (V75) — passive observer fields ──
  /// Raw backend takeover status, or `null` when there is no takeover.
  final String? takeoverRequestStatus;

  /// Nested takeover request detail; `null` when there is no takeover.
  final TakeoverRequest? pendingTakeoverRequest;
  final int? takeoverRemainingSeconds;
  final int? takeoverHandoverRemainingSeconds;
  final String? takeoverRequestedByOperatorName;
  final String? takeoverCurrentOperatorName;

  /// Backend-authoritative flag: when `true`, line work is blocked right now.
  final bool blocked;

  const BootstrapLineState({
    required this.lineId,
    required this.lineNumber,
    required this.lineName,
    this.isAuthorized = false,
    this.authorizedOperator,
    this.authorizedAt,
    this.sessionTable = const [],
    this.blockedReason,
    this.lineUiMode,
    this.hasOpenFalet = false,
    this.openFaletCount = 0,
    this.currentPlanItemId,
    this.currentPlanItemProductTypeId,
    this.currentPlanItemProductName,
    this.currentPlanItemPackagesPerPallet,
    this.defaultPackageQuantitySource,
    this.productionPlanBlocked = false,
    this.productionPlanBlockedReason,
    this.productionPlanBlockedMessage,
    this.waitingForOperator = false,
    this.waitingForOperatorReason,
    this.waitingForOperatorMessageTitle,
    this.waitingForOperatorMessage,
    this.takeoverRequestStatus,
    this.pendingTakeoverRequest,
    this.takeoverRemainingSeconds,
    this.takeoverHandoverRemainingSeconds,
    this.takeoverRequestedByOperatorName,
    this.takeoverCurrentOperatorName,
    this.blocked = false,
  });
}
