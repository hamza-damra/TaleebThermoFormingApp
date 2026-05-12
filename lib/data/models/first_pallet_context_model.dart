import '../../domain/entities/first_pallet_context.dart';

class FirstPalletContextModel extends FirstPalletContext {
  const FirstPalletContextModel({
    required super.lineId,
    super.currentProductTypeId,
    super.currentProductName,
    super.packageQuantity,
    super.hasOpenFalet,
    super.matchingProductFaletQuantity,
    super.nonMatchingFaletQuantity,
    super.canSuggestFirstPalletDialog,
    super.suggestedFaletQuantityForFirstPallet,
    super.requiresOperatorFaletDecision,
    super.messageAr,
    super.blockReason,
  });

  factory FirstPalletContextModel.fromJson(Map<String, dynamic> json) {
    return FirstPalletContextModel(
      lineId: json['lineId'] as int,
      currentProductTypeId: json['currentProductTypeId'] as int?,
      currentProductName: json['currentProductName'] as String?,
      packageQuantity: json['packageQuantity'] as int?,
      hasOpenFalet: json['hasOpenFalet'] as bool? ?? false,
      matchingProductFaletQuantity:
          json['matchingProductFaletQuantity'] as int? ?? 0,
      nonMatchingFaletQuantity: json['nonMatchingFaletQuantity'] as int? ?? 0,
      canSuggestFirstPalletDialog:
          json['canSuggestFirstPalletDialog'] as bool? ?? false,
      suggestedFaletQuantityForFirstPallet:
          json['suggestedFaletQuantityForFirstPallet'] as int?,
      requiresOperatorFaletDecision:
          json['requiresOperatorFaletDecision'] as bool? ?? false,
      messageAr: json['messageAr'] as String?,
      blockReason: json['blockReason'] as String?,
    );
  }
}
