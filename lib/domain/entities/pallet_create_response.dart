import 'falet_consumption.dart';
import 'grinding_order_summary.dart';
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
  final int? sessionProductSequence;

  /// Populated only when the create request carried a
  /// `firstPalletFaletConsumption` block and the backend successfully deducted
  /// the matching FALET in the same transaction. Null on every normal pallet
  /// creation.
  final FaletConsumption? faletConsumption;

  /// The grinding order created with the pallet when the request carried a
  /// `grindingRecommendation` (status `PENDING_APPROVAL`). Null for a normal
  /// pallet — and for an older backend that ignored the recommendation.
  final GrindingOrderSummary? grindingOrder;

  /// Label marker decided by the backend. All three are null on an older
  /// backend, which means "no marker, reprint allowed".
  final bool? grindingRecommended;
  final String? grindingLabelText;
  final bool? labelReprintAllowed;

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
    this.sessionProductSequence,
    this.faletConsumption,
    this.grindingOrder,
    this.grindingRecommended,
    this.grindingLabelText,
    this.labelReprintAllowed,
  });
}
