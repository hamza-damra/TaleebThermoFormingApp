import '../../domain/entities/falet_item.dart';

class FaletItemModel extends FaletItem {
  const FaletItemModel({
    required super.faletId,
    required super.productTypeId,
    required super.productTypeName,
    required super.quantity,
    required super.status,
    super.createdAt,
    super.createdAtDisplay,
    super.updatedAt,
    super.updatedAtDisplay,
  });

  factory FaletItemModel.fromJson(Map<String, dynamic> json) {
    return FaletItemModel(
      faletId: json['faletId'] as int,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      status: json['status'] as String? ?? 'OPEN',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      createdAtDisplay: json['createdAtDisplay'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      updatedAtDisplay: json['updatedAtDisplay'] as String?,
    );
  }
}
