import '../../domain/entities/falet_dispose_response.dart';

class FaletDisposeResponseModel extends FaletDisposeResponse {
  const FaletDisposeResponseModel({
    required super.faletId,
    required super.productTypeId,
    required super.productTypeName,
    required super.disposedQuantity,
    super.reason,
    super.disposedAt,
    super.disposedAtDisplay,
  });

  factory FaletDisposeResponseModel.fromJson(Map<String, dynamic> json) {
    return FaletDisposeResponseModel(
      faletId: json['faletId'] as int,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String? ?? '',
      disposedQuantity: json['disposedQuantity'] as int,
      reason: json['reason'] as String?,
      disposedAt: json['disposedAt'] != null
          ? DateTime.tryParse(json['disposedAt'] as String)
          : null,
      disposedAtDisplay: json['disposedAtDisplay'] as String?,
    );
  }
}
