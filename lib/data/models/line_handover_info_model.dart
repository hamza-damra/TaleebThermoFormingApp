import '../../domain/entities/line_handover_info.dart';

class LineHandoverInfoModel extends LineHandoverInfo {
  const LineHandoverInfoModel({
    required super.handoverId,
    required super.lineId,
    super.lineNumber,
    super.lineName,
    required super.status,
    super.statusDisplayNameAr,
    super.handoverType,
    super.outgoingOperatorName,
    super.outgoingOperatorId,
    super.incomingOperatorName,
    super.incomingOperatorId,
    super.incompletePallet,
    super.looseBalances,
    super.looseBalanceCount,
    super.hasIncompletePallet,
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
    final incompletePalletJson =
        json['incompletePallet'] as Map<String, dynamic>?;
    final looseBalancesJson = json['looseBalances'] as List<dynamic>? ?? [];

    return LineHandoverInfoModel(
      handoverId: json['handoverId'] as int? ?? json['id'] as int,
      lineId: json['lineId'] as int? ?? 0,
      lineNumber: json['lineNumber'] as int? ?? 0,
      lineName: json['lineName'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      statusDisplayNameAr: json['statusDisplayNameAr'] as String?,
      handoverType: json['handoverType'] as String?,
      outgoingOperatorName: json['outgoingOperatorName'] as String?,
      outgoingOperatorId: json['outgoingOperatorId'] as int?,
      incomingOperatorName: json['incomingOperatorName'] as String?,
      incomingOperatorId: json['incomingOperatorId'] as int?,
      incompletePallet: incompletePalletJson != null
          ? IncompletePalletInfoModel.fromJson(incompletePalletJson)
          : null,
      looseBalances: looseBalancesJson
          .map(
            (item) =>
                LooseBalanceItemModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      looseBalanceCount: json['looseBalanceCount'] as int? ?? 0,
      hasIncompletePallet: json['hasIncompletePallet'] as bool? ?? false,
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

class IncompletePalletInfoModel extends IncompletePalletInfo {
  const IncompletePalletInfoModel({
    super.productTypeId,
    required super.productTypeName,
    required super.quantity,
  });

  factory IncompletePalletInfoModel.fromJson(Map<String, dynamic> json) {
    return IncompletePalletInfoModel(
      productTypeId: json['productTypeId'] as int?,
      productTypeName: json['productTypeName'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
    );
  }
}

class LooseBalanceItemModel extends LooseBalanceItem {
  const LooseBalanceItemModel({
    required super.productTypeId,
    required super.productTypeName,
    required super.loosePackageCount,
  });

  factory LooseBalanceItemModel.fromJson(Map<String, dynamic> json) {
    return LooseBalanceItemModel(
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      loosePackageCount: json['loosePackageCount'] as int? ?? 0,
    );
  }
}
