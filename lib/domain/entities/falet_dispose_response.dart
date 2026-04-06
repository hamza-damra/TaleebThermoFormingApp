class FaletDisposeResponse {
  final int faletId;
  final int productTypeId;
  final String productTypeName;
  final int disposedQuantity;
  final String? reason;
  final DateTime? disposedAt;
  final String? disposedAtDisplay;

  const FaletDisposeResponse({
    required this.faletId,
    required this.productTypeId,
    required this.productTypeName,
    required this.disposedQuantity,
    this.reason,
    this.disposedAt,
    this.disposedAtDisplay,
  });
}
