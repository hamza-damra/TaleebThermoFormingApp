class Product {
  final int id;
  final String itemCode;
  final String name;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.itemCode,
    required this.name,
    this.imageUrl,
  });
}
