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
  final String? imageUrl;
  final String? description;

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
    this.imageUrl,
    this.description,
  }) : displayLabel = displayLabel ?? '$productName - $color ($packageQuantity $packageUnitDisplayName)';

  /// Short compact label for UI display: e.g. "TT-20 Black 30"
  String get compactLabel => '$productName $packageQuantity';

  /// Strips verbose slash-separated metadata from a raw product type name string.
  /// e.g. "TT-20 Black 500 / أسود / 30 كرتونة" → "TT-20 Black 500"
  static String formatCompactName(String verboseName) {
    if (verboseName.contains('/')) {
      return verboseName.split('/').first.trim();
    }
    return verboseName;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductType &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
