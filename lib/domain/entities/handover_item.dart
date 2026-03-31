class HandoverItem {
  final int id;
  final int productionLineId;
  final String productionLineName;
  final int productTypeId;
  final String productTypeName;
  final int quantity;
  final String? scannedValue;
  final String? notes;

  const HandoverItem({
    required this.id,
    required this.productionLineId,
    required this.productionLineName,
    required this.productTypeId,
    required this.productTypeName,
    required this.quantity,
    this.scannedValue,
    this.notes,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandoverItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
