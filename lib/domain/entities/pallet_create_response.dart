import 'operator.dart';
import 'product_type.dart';
import 'production_line.dart';

class PalletCreateResponse {
  final int palletId;
  final String scannedValue;
  final String? qrCodeData;
  final Operator operator;
  final ProductType productType;
  final ProductionLine productionLine;
  final int quantity;
  final String currentDestination;
  final DateTime createdAt;
  final String createdAtDisplay;

  const PalletCreateResponse({
    required this.palletId,
    required this.scannedValue,
    this.qrCodeData,
    required this.operator,
    required this.productType,
    required this.productionLine,
    required this.quantity,
    required this.currentDestination,
    required this.createdAt,
    required this.createdAtDisplay,
  });
}
