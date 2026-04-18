class FaletItem {
  final int faletId;
  final int productTypeId;
  final String productTypeName;
  final int quantity;
  final String status;
  final String? originType;
  final String? sourceOperatorName;
  final int? authorizationId;
  final bool managerResolved;
  final DateTime? createdAt;
  final String? createdAtDisplay;
  final DateTime? updatedAt;
  final String? updatedAtDisplay;

  const FaletItem({
    required this.faletId,
    required this.productTypeId,
    required this.productTypeName,
    required this.quantity,
    required this.status,
    this.originType,
    this.sourceOperatorName,
    this.authorizationId,
    this.managerResolved = false,
    this.createdAt,
    this.createdAtDisplay,
    this.updatedAt,
    this.updatedAtDisplay,
  });
}
