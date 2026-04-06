import '../../domain/entities/line_handover_info.dart';

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
    super.notes,
    super.rejectionNotes,
    super.resolutionNotes,
    super.resolvedByUserName,
    super.createdAt,
    super.createdAtDisplay,
    super.confirmedAtDisplay,
    super.rejectedAtDisplay,
    super.resolvedAtDisplay,
  });

  factory LineHandoverInfoModel.fromJson(Map<String, dynamic> json) {
    final faletItemsJson = json['faletItems'] as List<dynamic>? ?? [];

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
            (item) => HandoverFaletItemModel.fromJson(
                item as Map<String, dynamic>),
          )
          .toList(),
      faletItemCount: json['faletItemCount'] as int? ?? 0,
      hasFalet: json['hasFalet'] as bool? ?? false,
      notes: json['notes'] as String?,
      rejectionNotes: json['rejectionNotes'] as String?,
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
    required super.faletId,
    required super.productTypeId,
    required super.productTypeName,
    required super.quantity,
    super.lastActiveProduct,
  });

  factory HandoverFaletItemModel.fromJson(Map<String, dynamic> json) {
    return HandoverFaletItemModel(
      faletId: json['faletId'] as int,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      lastActiveProduct: json['lastActiveProduct'] as bool? ?? false,
    );
  }
}
