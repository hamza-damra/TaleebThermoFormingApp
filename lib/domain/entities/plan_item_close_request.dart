/// Status of a Thermoforming operator's request to close the current
/// production-plan item (V190 plan-item close handshake).
///
/// `unknown` is the safety fallback so a status added by a future backend
/// never crashes the app — it is treated as "not active".
enum PlanItemCloseRequestStatus {
  /// The operator asked to close the item; the palletizer must answer.
  waitingForPalletizerDecision,

  /// The palletizer reported that pallets remain; the item stays current
  /// until the palletizer confirms that every pallet is registered.
  palletizerCompletingPallets,
  confirmed,
  cancelled,
  invalidated,
  unknown;

  /// Maps the backend wire value. Anything unrecognised → [unknown].
  static PlanItemCloseRequestStatus fromString(String? raw) {
    switch (raw) {
      case 'WAITING_FOR_PALLETIZER_DECISION':
        return PlanItemCloseRequestStatus.waitingForPalletizerDecision;
      case 'PALLETIZER_COMPLETING_PALLETS':
        return PlanItemCloseRequestStatus.palletizerCompletingPallets;
      case 'CONFIRMED':
        return PlanItemCloseRequestStatus.confirmed;
      case 'CANCELLED':
        return PlanItemCloseRequestStatus.cancelled;
      case 'INVALIDATED':
        return PlanItemCloseRequestStatus.invalidated;
      default:
        return PlanItemCloseRequestStatus.unknown;
    }
  }

  /// The two statuses the pending-request read can return — the only ones
  /// that put a dialog or a banner on screen.
  bool get isActive =>
      this == PlanItemCloseRequestStatus.waitingForPalletizerDecision ||
      this == PlanItemCloseRequestStatus.palletizerCompletingPallets;
}

/// The Palletizing App's view of a plan-item close request
/// (`PalletizerPlanItemCloseRequestResponse`).
///
/// Deliberately carries no close reason, notes, roll decision or roll weight —
/// the palletizer only answers whether every produced pallet is registered.
/// Instants are absolute (UTC on the wire).
class PlanItemCloseRequest {
  final int closeRequestId;
  final PlanItemCloseRequestStatus status;

  /// The plan item being closed. It stays the line's current item while the
  /// request is active, so it equals the line state's `currentPlanItemId`.
  final int productionPlanItemId;
  final int? productTypeId;
  final String? productTypeName;
  final int targetPackageQuantity;

  /// Live produced packages of the item at read time.
  final int producedPackageQuantity;
  final int? thermoformingLineId;
  final int palletizingLineId;
  final String? requestedByOperatorName;
  final DateTime? requestedAt;
  final DateTime? morePalletsReportedAt;
  final String? morePalletsReportedByName;
  final DateTime? confirmedAt;
  final String? confirmedByPalletizerName;
  final int? resultingNextItemId;

  /// Backend `invalidationReason` wire value, present on `INVALIDATED`. Kept
  /// raw: the palletizer UI shows one generic "no longer valid" notice.
  final String? invalidationReason;

  /// `true` on a decision response that had already been applied (a retried
  /// decision). Handled exactly like a first-time success.
  final bool alreadyProcessed;

  const PlanItemCloseRequest({
    required this.closeRequestId,
    required this.status,
    required this.productionPlanItemId,
    required this.palletizingLineId,
    this.productTypeId,
    this.productTypeName,
    this.targetPackageQuantity = 0,
    this.producedPackageQuantity = 0,
    this.thermoformingLineId,
    this.requestedByOperatorName,
    this.requestedAt,
    this.morePalletsReportedAt,
    this.morePalletsReportedByName,
    this.confirmedAt,
    this.confirmedByPalletizerName,
    this.resultingNextItemId,
    this.invalidationReason,
    this.alreadyProcessed = false,
  });

  bool get isWaitingForDecision =>
      status == PlanItemCloseRequestStatus.waitingForPalletizerDecision;

  bool get isCompletingPallets =>
      status == PlanItemCloseRequestStatus.palletizerCompletingPallets;

  @override
  String toString() =>
      'PlanItemCloseRequest(id: $closeRequestId, status: $status, '
      'item: $productionPlanItemId, line: $palletizingLineId)';
}
