class ProductType {
  final int id;
  final String name;
  final String productName;
  final String prefix;
  final String color;
  final int packageQuantity;
  final String packageUnit;
  final String packageUnitDisplayName;
  final String displayLabel;

  ProductType({
    required this.id,
    required this.name,
    required this.productName,
    required this.prefix,
    required this.color,
    required this.packageQuantity,
    required this.packageUnit,
    required this.packageUnitDisplayName,
    String? displayLabel,
  }) : displayLabel = displayLabel ?? '$productName - $color ($packageQuantity $packageUnitDisplayName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductType &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
