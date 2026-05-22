class FirstPalletContext {
  final int lineId;
  final int? currentPlanItemId;
  final int? currentPlanItemProductTypeId;
  final String? currentPlanItemProductName;
  final int? currentPlanItemPackagesPerPallet;
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
    this.currentPlanItemId,
    this.currentPlanItemProductTypeId,
    this.currentPlanItemProductName,
    this.currentPlanItemPackagesPerPallet,
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
