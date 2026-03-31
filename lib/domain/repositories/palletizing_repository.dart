import '../entities/operator.dart';
import '../entities/product_type.dart';
import '../entities/production_line.dart';
import '../entities/pallet_create_response.dart';
import '../entities/line_summary.dart';
import '../entities/print_attempt_result.dart';

abstract class PalletizingRepository {
  Future<List<Operator>> getOperators();
  Future<List<ProductType>> getProductTypes();
  Future<List<ProductionLine>> getProductionLines();
  Future<PalletCreateResponse> createPallet({
    required int operatorId,
    required int productTypeId,
    required int productionLineId,
    required int quantity,
  });
  Future<PrintAttemptResult> logPrintAttempt({
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  });
  Future<LineSummary> getLineSummary(int lineId);
}
