import '../../domain/entities/session_production_detail.dart';

class SessionPalletDetailModel extends SessionPalletDetail {
  const SessionPalletDetailModel({
    required super.palletId,
    required super.scannedValue,
    required super.serialNumber,
    required super.quantity,
    required super.sourceType,
    required super.createdAt,
    required super.createdAtDisplay,
  });

  factory SessionPalletDetailModel.fromJson(Map<String, dynamic> json) {
    return SessionPalletDetailModel(
      palletId: json['palletId'] as int,
      scannedValue: json['scannedValue'] as String,
      serialNumber: json['serialNumber'] as String,
      quantity: json['quantity'] as int,
      sourceType: json['sourceType'] as String? ?? 'UNKNOWN',
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdAtDisplay: json['createdAtDisplay'] as String? ?? '',
    );
  }
}

class SessionProductTypeGroupModel extends SessionProductTypeGroup {
  const SessionProductTypeGroupModel({
    required super.productTypeId,
    required super.productTypeName,
    required super.productTypePrefix,
    required super.completedPalletCount,
    required super.pallets,
  });

  factory SessionProductTypeGroupModel.fromJson(Map<String, dynamic> json) {
    final palletsJson = json['pallets'] as List<dynamic>? ?? [];
    return SessionProductTypeGroupModel(
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String,
      productTypePrefix: json['productTypePrefix'] as String? ?? '',
      completedPalletCount: json['completedPalletCount'] as int? ?? 0,
      pallets: palletsJson
          .map((p) =>
              SessionPalletDetailModel.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SessionProductionDetailModel extends SessionProductionDetail {
  const SessionProductionDetailModel({
    required super.lineId,
    required super.authorizationId,
    required super.groups,
  });

  factory SessionProductionDetailModel.fromJson(Map<String, dynamic> json) {
    final groupsJson = json['groups'] as List<dynamic>? ?? [];
    return SessionProductionDetailModel(
      lineId: json['lineId'] as int,
      authorizationId: json['authorizationId'] as int,
      groups: groupsJson
          .map((g) => SessionProductTypeGroupModel.fromJson(
              g as Map<String, dynamic>))
          .toList(),
    );
  }
}
