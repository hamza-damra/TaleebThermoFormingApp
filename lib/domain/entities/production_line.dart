class ProductionLine {
  final int id;
  final String name;
  final String code;
  final int lineNumber;

  const ProductionLine({
    required this.id,
    required this.name,
    required this.code,
    required this.lineNumber,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductionLine &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
