import '../../domain/entities/reconciled_falet_item.dart';

class ReconciledFaletItemModel extends ReconciledFaletItem {
  const ReconciledFaletItemModel({
    required super.faletId,
    super.palleteId,
    super.scannedValue,
    required super.productTypeId,
    required super.productTypeName,
    required super.reconciledQuantity,
    super.resolutionType,
  });

  factory ReconciledFaletItemModel.fromJson(Map<String, dynamic> json) {
    return ReconciledFaletItemModel(
      faletId: json['faletId'] as int,
      palleteId: json['palleteId'] as int?,
      scannedValue: json['scannedValue'] as String?,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      reconciledQuantity: json['reconciledQuantity'] as int? ?? 0,
      resolutionType:
          json['resolutionType'] as String? ?? 'PALLET_RECONCILIATION',
    );
  }
}
