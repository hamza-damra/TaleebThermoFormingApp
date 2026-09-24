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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionTableRow &&
          productTypeId == other.productTypeId &&
          productTypeName == other.productTypeName &&
          completedPalletCount == other.completedPalletCount &&
          completedPackageCount == other.completedPackageCount &&
          loosePackageCount == other.loosePackageCount;

  @override
  int get hashCode => Object.hash(
    productTypeId,
    productTypeName,
    completedPalletCount,
    completedPackageCount,
    loosePackageCount,
  );
}
