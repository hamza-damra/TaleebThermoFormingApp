class LooseBalanceItem {
  final int productTypeId;
  final String productTypeName;
  final int loosePackageCount;
  final String origin;
  final int? sourceHandoverId;

  const LooseBalanceItem({
    required this.productTypeId,
    required this.productTypeName,
    required this.loosePackageCount,
    required this.origin,
    this.sourceHandoverId,
  });

  bool get isFromHandover => origin == 'CARRIED_FROM_HANDOVER';
}
