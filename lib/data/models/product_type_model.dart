import '../../domain/entities/product_type.dart';

class ProductTypeModel extends ProductType {
  ProductTypeModel({
    required super.id,
    required super.name,
    required super.productName,
    required super.prefix,
    required super.color,
    required super.packageQuantity,
    required super.packageUnit,
    required super.packageUnitDisplayName,
    super.displayLabel,
    super.imageUrl,
  });

  factory ProductTypeModel.fromJson(Map<String, dynamic> json) {
    return ProductTypeModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      color: json['color'] as String? ?? '',
      packageQuantity: json['packageQuantity'] as int? ?? 0,
      packageUnit: json['packageUnit'] as String? ?? '',
      packageUnitDisplayName: json['packageUnitDisplayName'] as String? ?? '',
      displayLabel: json['displayLabel'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
