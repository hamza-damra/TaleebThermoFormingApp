class SessionPalletDetail {
  final int palletId;
  final String scannedValue;
  final String serialNumber;
  final int quantity;
  final String sourceType;
  final DateTime createdAt;
  final String createdAtDisplay;

  const SessionPalletDetail({
    required this.palletId,
    required this.scannedValue,
    required this.serialNumber,
    required this.quantity,
    required this.sourceType,
    required this.createdAt,
    required this.createdAtDisplay,
  });
}

class SessionProductTypeGroup {
  final int productTypeId;
  final String productTypeName;
  final String productTypePrefix;
  final int completedPalletCount;
  final List<SessionPalletDetail> pallets;

  const SessionProductTypeGroup({
    required this.productTypeId,
    required this.productTypeName,
    required this.productTypePrefix,
    required this.completedPalletCount,
    required this.pallets,
  });
}

class SessionProductionDetail {
  final int lineId;
  final int authorizationId;
  final List<SessionProductTypeGroup> groups;

  const SessionProductionDetail({
    required this.lineId,
    required this.authorizationId,
    required this.groups,
  });
}
