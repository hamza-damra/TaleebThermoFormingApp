import '../../domain/entities/product.dart';

class ProductModel extends Product {
  const ProductModel({
    required super.id,
    required super.itemCode,
    required super.name,
    super.imageUrl,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as int,
      itemCode: json['item_code'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String?,
    );
  }
}
