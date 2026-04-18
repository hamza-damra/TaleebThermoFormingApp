import '../../domain/entities/first_pallet_suggestion.dart';

class FirstPalletSuggestionModel extends FirstPalletSuggestion {
  const FirstPalletSuggestionModel({
    required super.available,
    super.faletId,
    super.productTypeId,
    super.productTypeName,
    super.approvedCartons,
    super.defaultPalletQuantity,
    super.suggestedFreshQuantity,
    super.sourceOperatorName,
    super.originType,
    super.matchType,
    super.unavailableReason,
  });

  factory FirstPalletSuggestionModel.fromJson(Map<String, dynamic> json) {
    return FirstPalletSuggestionModel(
      available: json['available'] as bool? ?? false,
      faletId: json['faletId'] as int?,
      productTypeId: json['productTypeId'] as int?,
      productTypeName: json['productTypeName'] as String?,
      approvedCartons: json['approvedCartons'] as int?,
      defaultPalletQuantity: json['defaultPalletQuantity'] as int?,
      suggestedFreshQuantity: json['suggestedFreshQuantity'] as int?,
      sourceOperatorName: json['sourceOperatorName'] as String?,
      originType: json['originType'] as String?,
      matchType: json['matchType'] as String?,
      unavailableReason: json['unavailableReason'] as String?,
    );
  }
}
