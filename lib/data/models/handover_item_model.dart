import '../../domain/entities/handover_item.dart';

class HandoverItemModel extends HandoverItem {
  const HandoverItemModel({
    required super.id,
    required super.productionLineId,
    required super.productionLineName,
    required super.productTypeId,
    required super.productTypeName,
    required super.quantity,
    super.scannedValue,
    super.notes,
  });

  factory HandoverItemModel.fromJson(Map<String, dynamic> json) {
    return HandoverItemModel(
      id: json['id'] as int,
      productionLineId: json['productionLineId'] as int,
      productionLineName: (json['productionLineName'] as String?) ?? '',
      productTypeId: json['productTypeId'] as int,
      productTypeName: (json['productTypeName'] as String?) ?? '',
      quantity: (json['quantity'] as int?) ?? 0,
      scannedValue: json['scannedValue'] as String?,
      notes: json['notes'] as String?,
    );
  }
}
