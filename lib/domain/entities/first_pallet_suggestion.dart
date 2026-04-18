class FirstPalletSuggestion {
  final bool available;
  final int? faletId;
  final int? productTypeId;
  final String? productTypeName;
  final int? approvedCartons;
  final int? defaultPalletQuantity;
  final int? suggestedFreshQuantity;
  final String? sourceOperatorName;
  final String? originType;
  final String? matchType;
  final String? unavailableReason;

  const FirstPalletSuggestion({
    required this.available,
    this.faletId,
    this.productTypeId,
    this.productTypeName,
    this.approvedCartons,
    this.defaultPalletQuantity,
    this.suggestedFreshQuantity,
    this.sourceOperatorName,
    this.originType,
    this.matchType,
    this.unavailableReason,
  });

  bool get isSameSessionReturn => matchType == 'SAME_SESSION_RETURN';
  bool get isConfirmedHandover => matchType == 'CONFIRMED_HANDOVER';
}
