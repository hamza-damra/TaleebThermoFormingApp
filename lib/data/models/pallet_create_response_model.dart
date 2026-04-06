import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';

class PalletCreateResponseModel extends PalletCreateResponse {
  const PalletCreateResponseModel({
    required super.palletId,
    required super.scannedValue,
    super.qrCodeData,
    required super.operator,
    required super.productType,
    required super.productionLine,
    required super.quantity,
    required super.currentDestination,
    required super.createdAt,
    required super.createdAtDisplay,
  });

  factory PalletCreateResponseModel.fromJson(Map<String, dynamic> json) {
    final operatorJson = json['operator'] as Map<String, dynamic>;
    final productTypeJson = json['productType'] as Map<String, dynamic>;
    final productionLineJson = json['productionLine'] as Map<String, dynamic>;

    return PalletCreateResponseModel(
      palletId: json['palletId'] as int,
      scannedValue: json['scannedValue'] as String,
      qrCodeData: json['qrCodeData'] as String?,
      operator: Operator(
        id: operatorJson['id'] as int,
        name: operatorJson['name'] as String,
      ),
      productType: ProductType(
        id: productTypeJson['id'] as int,
        name: productTypeJson['name'] as String,
        productName: productTypeJson['productName'] as String? ?? '',
        prefix: productTypeJson['prefix'] as String? ?? '',
        color: productTypeJson['color'] as String? ?? '',
        packageQuantity: productTypeJson['packageQuantity'] as int? ?? 0,
        packageUnit: productTypeJson['packageUnit'] as String? ?? '',
        packageUnitDisplayName:
            productTypeJson['packageUnitDisplayName'] as String? ?? '',
        imageUrl: productTypeJson['imageUrl'] as String?,
      ),
      productionLine: ProductionLine(
        id: productionLineJson['id'] as int,
        name: productionLineJson['name'] as String,
        code: productionLineJson['code'] as String? ?? '',
        lineNumber: productionLineJson['lineNumber'] as int,
      ),
      quantity: json['quantity'] as int,
      currentDestination: json['currentDestination'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdAtDisplay: json['createdAtDisplay'] as String? ?? '',
    );
  }
}
