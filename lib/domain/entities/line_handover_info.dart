import 'reconciled_falet_item.dart';

class LineHandoverInfo {
  final int handoverId;
  final int lineId;
  final int lineNumber;
  final String? lineName;
  final String status;
  final String? statusDisplayNameAr;
  final String? outgoingOperatorName;
  final int? outgoingOperatorId;
  final String? incomingOperatorName;
  final int? incomingOperatorId;
  final List<HandoverFaletItem> faletItems;
  final int faletItemCount;
  final bool hasFalet;
  final List<ReconciledFaletItem> reconciledFaletItems;
  final String? notes;
  final String? rejectionNotes;
  final String? receiptNotes;
  final bool? rejectionIncorrectQuantity;
  final bool? rejectionOtherReason;
  final String? rejectionOtherReasonNotes;
  final bool? rejectionUndeclaredFalet;
  final String? resolutionNotes;
  final String? resolvedByUserName;
  final DateTime? createdAt;
  final String? createdAtDisplay;
  final String? confirmedAtDisplay;
  final String? rejectedAtDisplay;
  final String? resolvedAtDisplay;

  const LineHandoverInfo({
    required this.handoverId,
    required this.lineId,
    this.lineNumber = 0,
    this.lineName,
    required this.status,
    this.statusDisplayNameAr,
    this.outgoingOperatorName,
    this.outgoingOperatorId,
    this.incomingOperatorName,
    this.incomingOperatorId,
    this.faletItems = const [],
    this.faletItemCount = 0,
    this.hasFalet = false,
    this.reconciledFaletItems = const [],
    this.notes,
    this.rejectionNotes,
    this.receiptNotes,
    this.rejectionIncorrectQuantity,
    this.rejectionOtherReason,
    this.rejectionOtherReasonNotes,
    this.rejectionUndeclaredFalet,
    this.resolutionNotes,
    this.resolvedByUserName,
    this.createdAt,
    this.createdAtDisplay,
    this.confirmedAtDisplay,
    this.rejectedAtDisplay,
    this.resolvedAtDisplay,
  });

  bool get isPending => status == 'PENDING';
}

class HandoverFaletItem {
  /// Primary key of the `line_handover_falet_snapshots` row. This is the value
  /// that must be sent as `faletSnapshotId` in handover-reject observations —
  /// never confuse it with [faletId], which is the FALET state FK.
  final int faletSnapshotId;
  final int faletId;
  final int productTypeId;
  final String productTypeName;
  final int quantity;
  final int? observedQuantity;
  final bool lastActiveProduct;

  const HandoverFaletItem({
    required this.faletSnapshotId,
    required this.faletId,
    required this.productTypeId,
    required this.productTypeName,
    required this.quantity,
    this.observedQuantity,
    this.lastActiveProduct = false,
  });
}
