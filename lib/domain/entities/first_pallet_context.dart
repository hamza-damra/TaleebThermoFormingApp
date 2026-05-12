class FirstPalletContext {
  final int lineId;
  final int? currentProductTypeId;
  final String? currentProductName;
  final int? packageQuantity;
  final bool hasOpenFalet;
  final int matchingProductFaletQuantity;
  final int nonMatchingFaletQuantity;
  final bool canSuggestFirstPalletDialog;
  final int? suggestedFaletQuantityForFirstPallet;
  final bool requiresOperatorFaletDecision;
  final String? messageAr;
  final String? blockReason;

  const FirstPalletContext({
    required this.lineId,
    this.currentProductTypeId,
    this.currentProductName,
    this.packageQuantity,
    this.hasOpenFalet = false,
    this.matchingProductFaletQuantity = 0,
    this.nonMatchingFaletQuantity = 0,
    this.canSuggestFirstPalletDialog = false,
    this.suggestedFaletQuantityForFirstPallet,
    this.requiresOperatorFaletDecision = false,
    this.messageAr,
    this.blockReason,
  });
}
