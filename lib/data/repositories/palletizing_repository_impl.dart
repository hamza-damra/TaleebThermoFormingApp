import '../../domain/entities/operator.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/line_summary.dart';
import '../../domain/entities/print_attempt_result.dart';
import '../../domain/repositories/palletizing_repository.dart';
import '../datasources/api_client.dart';
import '../models/operator_model.dart';
import '../models/product_type_model.dart';
import '../models/production_line_model.dart';
import '../models/pallet_create_response_model.dart';
import '../models/line_summary_model.dart';
import '../models/print_attempt_result_model.dart';

class PalletizingRepositoryImpl implements PalletizingRepository {
  final ApiClient _apiClient;

  PalletizingRepositoryImpl({required ApiClient apiClient})
      : _apiClient = apiClient;

  @override
  Future<List<Operator>> getOperators() async {
    return await _apiClient.requestList<Operator>(
      path: '/palletizing/operators',
      method: 'GET',
      itemParser: (json) => OperatorModel.fromJson(json),
    );
  }

  @override
  Future<List<ProductType>> getProductTypes() async {
    return await _apiClient.requestList<ProductType>(
      path: '/palletizing/product-types',
      method: 'GET',
      itemParser: (json) => ProductTypeModel.fromJson(json),
    );
  }

  @override
  Future<List<ProductionLine>> getProductionLines() async {
    return await _apiClient.requestList<ProductionLine>(
      path: '/palletizing/production-lines',
      method: 'GET',
      itemParser: (json) => ProductionLineModel.fromJson(json),
    );
  }

  @override
  Future<PalletCreateResponse> createPallet({
    required int operatorId,
    required int productTypeId,
    required int productionLineId,
    required int quantity,
  }) async {
    return await _apiClient.request<PalletCreateResponse>(
      path: '/palletizing/pallets',
      method: 'POST',
      data: {
        'operatorId': operatorId,
        'productTypeId': productTypeId,
        'productionLineId': productionLineId,
        'quantity': quantity,
      },
      parser: (json) => PalletCreateResponseModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<PrintAttemptResult> logPrintAttempt({
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  }) async {
    return await _apiClient.request<PrintAttemptResult>(
      path: '/palletizing/pallets/$palletId/print-attempts',
      method: 'POST',
      data: {
        'printerIdentifier': printerIdentifier,
        'status': status,
        if (failureReason != null) 'failureReason': failureReason,
      },
      parser: (json) => PrintAttemptResultModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<LineSummary> getLineSummary(int lineId) async {
    return await _apiClient.request<LineSummary>(
      path: '/palletizing/lines/$lineId/summary',
      method: 'GET',
      parser: (json) => LineSummaryModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }
}
