class ReconciledFaletItem {
  final int faletId;
  final int? palleteId;
  final String? scannedValue;
  final int productTypeId;
  final String productTypeName;
  final int reconciledQuantity;
  final String resolutionType;

  const ReconciledFaletItem({
    required this.faletId,
    this.palleteId,
    this.scannedValue,
    required this.productTypeId,
    required this.productTypeName,
    required this.reconciledQuantity,
    this.resolutionType = 'PALLET_RECONCILIATION',
  });

  bool get isSessionAccounted => resolutionType == 'SESSION_ACCOUNTED';
}
