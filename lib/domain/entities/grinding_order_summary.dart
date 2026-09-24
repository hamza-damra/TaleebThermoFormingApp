/// Compact grinding-order block the backend embeds in a create-pallet
/// response when the pallet was registered with a grinding recommendation
/// (Unified Grinding Lifecycle). Absent for every normal pallet.
///
/// Informational only: the label marker and reprint permission come from the
/// top-level `grindingRecommended` / `grindingLabelText` /
/// `labelReprintAllowed` fields, never from [status].
class GrindingOrderSummary {
  final int id;

  /// e.g. `GR-001043`.
  final String orderNumber;

  /// e.g. `PENDING_APPROVAL`.
  final String status;

  /// Arabic status text from the backend, shown verbatim.
  final String? statusLabel;
  final String? sourceType;
  final String? sourceOrigin;
  final String? creationBasis;
  final bool managerApprovalRequired;
  final bool legacy;

  const GrindingOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.sourceType,
    this.sourceOrigin,
    this.creationBasis,
    this.managerApprovalRequired = false,
    this.legacy = false,
  });
}
