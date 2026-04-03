class SessionTableRow {
  final int productTypeId;
  final String productTypeName;
  final int completedPalletCount;
  final int completedPackageCount;
  final int loosePackageCount;

  const SessionTableRow({
    required this.productTypeId,
    required this.productTypeName,
    required this.completedPalletCount,
    required this.completedPackageCount,
    required this.loosePackageCount,
  });

  bool get hasLooseBalance => loosePackageCount > 0;
}
