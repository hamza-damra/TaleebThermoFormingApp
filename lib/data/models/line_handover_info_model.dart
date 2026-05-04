import '../../domain/entities/line_handover_info.dart';
import 'reconciled_falet_item_model.dart';

class LineHandoverInfoModel extends LineHandoverInfo {
  const LineHandoverInfoModel({
    required super.handoverId,
    required super.lineId,
    super.lineNumber,
    super.lineName,
    required super.status,
    super.statusDisplayNameAr,
    super.outgoingOperatorName,
    super.outgoingOperatorId,
    super.incomingOperatorName,
    super.incomingOperatorId,
    super.faletItems,
    super.faletItemCount,
    super.hasFalet,
    super.reconciledFaletItems,
    super.notes,
    super.rejectionNotes,
    super.receiptNotes,
    super.rejectionIncorrectQuantity,
    super.rejectionOtherReason,
    super.rejectionOtherReasonNotes,
    super.rejectionUndeclaredFalet,
    super.resolutionNotes,
    super.resolvedByUserName,
    super.createdAt,
    super.createdAtDisplay,
    super.confirmedAtDisplay,
    super.rejectedAtDisplay,
    super.resolvedAtDisplay,
  });

  factory LineHandoverInfoModel.fromJson(Map<String, dynamic> json) {
    // Some backend revisions serialize snapshots under `faletSnapshots[]`
    // instead of (or alongside) `faletItems[]`. Prefer the new key when
    // present so the reject flow can recover the snapshot row IDs.
    final faletItemsJson = (json['faletSnapshots'] as List<dynamic>?) ??
        (json['faletItems'] as List<dynamic>? ?? []);
    final reconciledJson = json['reconciledFaletItems'] as List<dynamic>? ?? [];

    return LineHandoverInfoModel(
      handoverId: json['handoverId'] as int? ?? json['id'] as int,
      lineId: json['lineId'] as int? ?? 0,
      lineNumber: json['lineNumber'] as int? ?? 0,
      lineName: json['lineName'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      statusDisplayNameAr: json['statusDisplayNameAr'] as String?,
      outgoingOperatorName: json['outgoingOperatorName'] as String?,
      outgoingOperatorId: json['outgoingOperatorId'] as int?,
      incomingOperatorName: json['incomingOperatorName'] as String?,
      incomingOperatorId: json['incomingOperatorId'] as int?,
      faletItems: faletItemsJson
          .map(
            (item) =>
                HandoverFaletItemModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      faletItemCount: json['faletItemCount'] as int? ?? 0,
      hasFalet: json['hasFalet'] as bool? ?? false,
      reconciledFaletItems: reconciledJson
          .map(
            (item) =>
                ReconciledFaletItemModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      notes: json['notes'] as String?,
      rejectionNotes: json['rejectionNotes'] as String?,
      receiptNotes: json['receiptNotes'] as String?,
      rejectionIncorrectQuantity: json['rejectionIncorrectQuantity'] as bool?,
      rejectionOtherReason: json['rejectionOtherReason'] as bool?,
      rejectionOtherReasonNotes: json['rejectionOtherReasonNotes'] as String?,
      rejectionUndeclaredFalet: json['rejectionUndeclaredFalet'] as bool?,
      resolutionNotes: json['resolutionNotes'] as String?,
      resolvedByUserName: json['resolvedByUserName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      createdAtDisplay: json['createdAtDisplay'] as String?,
      confirmedAtDisplay: json['confirmedAtDisplay'] as String?,
      rejectedAtDisplay: json['rejectedAtDisplay'] as String?,
      resolvedAtDisplay: json['resolvedAtDisplay'] as String?,
    );
  }
}

class HandoverFaletItemModel extends HandoverFaletItem {
  const HandoverFaletItemModel({
    required super.faletSnapshotId,
    required super.faletId,
    required super.productTypeId,
    required super.productTypeName,
    required super.quantity,
    super.observedQuantity,
    super.lastActiveProduct,
  });

  factory HandoverFaletItemModel.fromJson(Map<String, dynamic> json) {
    final faletId = json['faletId'] as int;
    // The snapshot's primary key may be serialized under any of these field
    // names depending on backend version: `faletSnapshotId`, `snapshotId`,
    // `id`. Fall back to `faletId` only as a last resort — sending the FALET
    // FK as the snapshot id is the production-#79 bug this contract was
    // tightened to prevent.
    final snapshotId = (json['faletSnapshotId'] as int?) ??
        (json['snapshotId'] as int?) ??
        (json['id'] as int?) ??
        faletId;
    return HandoverFaletItemModel(
      faletSnapshotId: snapshotId,
      faletId: faletId,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      observedQuantity: json['observedQuantity'] as int?,
      lastActiveProduct: json['lastActiveProduct'] as bool? ?? false,
    );
  }
}
