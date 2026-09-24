import '../../domain/entities/pallet_label.dart';

class PalletLabelModel extends PalletLabel {
  const PalletLabelModel({
    required super.palletId,
    required super.scannedValue,
    super.productTypeId,
    required super.productTypeName,
    required super.productTypePrefix,
    super.packageQuantity,
    super.packageUnit,
    super.packageUnitDisplayName,
    required super.quantity,
    super.productionLineId,
    required super.productionLineName,
    required super.operatorName,
    required super.createdAt,
    required super.createdAtDisplay,
    super.grindingRecommended,
    super.grindingLabelText,
    super.labelReprintAllowed,
  });

  /// Defensive parser — `@JsonInclude(NON_NULL)` on the backend means nullable
  /// fields are **absent** from the JSON rather than `null`. Read each nullable
  /// field with an explicit null fallback.
  factory PalletLabelModel.fromJson(Map<String, dynamic> json) {
    return PalletLabelModel(
      palletId: json['palletId'] as int,
      scannedValue: json['scannedValue'] as String,
      productTypeId: json['productTypeId'] as int?,
      productTypeName: json['productTypeName'] as String? ?? '',
      productTypePrefix: json['productTypePrefix'] as String? ?? '',
      packageQuantity: json['packageQuantity'] as int?,
      packageUnit: json['packageUnit'] as String?,
      packageUnitDisplayName: json['packageUnitDisplayName'] as String?,
      quantity: json['quantity'] as int,
      productionLineId: json['productionLineId'] as int?,
      productionLineName: json['productionLineName'] as String? ?? '',
      operatorName: json['operatorName'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdAtDisplay: json['createdAtDisplay'] as String? ?? '',
      grindingRecommended: json['grindingRecommended'] as bool?,
      grindingLabelText: json['grindingLabelText'] as String?,
      labelReprintAllowed: json['labelReprintAllowed'] as bool?,
    );
  }
}
