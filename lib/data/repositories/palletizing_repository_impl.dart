import '../../domain/entities/bootstrap_response.dart';
import '../../domain/entities/complete_incomplete_pallet_response.dart';
import '../../domain/entities/line_authorization_state.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/open_items_response.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/print_attempt_result.dart';
import '../../domain/entities/produce_pallet_from_loose_response.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart';
import '../../domain/entities/session_table_row.dart';
import '../../domain/repositories/palletizing_repository.dart';
import '../datasources/api_client.dart';
import '../models/bootstrap_response_model.dart';
import '../models/complete_incomplete_pallet_response_model.dart';
import '../models/line_handover_info_model.dart';
import '../models/open_items_response_model.dart';
import '../models/operator_model.dart';
import '../models/pallet_create_response_model.dart';
import '../models/print_attempt_result_model.dart';
import '../models/produce_pallet_from_loose_response_model.dart';
import '../models/product_type_model.dart';
import '../models/production_line_model.dart';
import '../models/session_table_row_model.dart';

class PalletizingRepositoryImpl implements PalletizingRepository {
  final ApiClient _apiClient;

  PalletizingRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  // ── Legacy endpoints (kept for adjacent flows) ──

  Future<List<Operator>> getOperators() async {
    return await _apiClient.requestList<Operator>(
      path: '/palletizing/operators',
      method: 'GET',
      itemParser: (json) => OperatorModel.fromJson(json),
    );
  }

  Future<List<ProductType>> getProductTypes() async {
    return await _apiClient.requestList<ProductType>(
      path: '/palletizing/product-types',
      method: 'GET',
      itemParser: (json) => ProductTypeModel.fromJson(json),
    );
  }

  Future<List<ProductionLine>> getProductionLines() async {
    return await _apiClient.requestList<ProductionLine>(
      path: '/palletizing/production-lines',
      method: 'GET',
      itemParser: (json) => ProductionLineModel.fromJson(json),
    );
  }

  // ── New line-scoped endpoints (/palletizing-line) ──

  @override
  Future<BootstrapResponse> bootstrap() async {
    return await _apiClient.request<BootstrapResponse>(
      path: '/palletizing-line/bootstrap',
      method: 'GET',
      parser: (json) =>
          BootstrapResponseModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<LineAuthorizationState> authorizeLine({
    required int lineId,
    required String pin,
  }) async {
    return await _apiClient.request<LineAuthorizationState>(
      path: '/palletizing-line/lines/$lineId/authorize-pin',
      method: 'POST',
      data: {'pin': pin},
      parser: (json) {
        final data = json['data'] as Map<String, dynamic>;
        // Backend may return operator as nested object or just operatorName string
        final operatorJson = data['operator'] as Map<String, dynamic>?;
        Operator? operator;
        if (operatorJson != null) {
          operator = OperatorModel.fromJson(operatorJson);
        } else {
          // Fallback: construct Operator from flat operatorName/operatorId fields
          final operatorName = data['operatorName'] as String?;
          final operatorId = data['operatorId'] as int?;
          if (operatorName != null) {
            operator = OperatorModel(
              id: operatorId ?? 0,
              name: operatorName,
              code: '',
              displayLabel: operatorName,
            );
          }
        }
        return LineAuthorizationState(
          lineId: data['lineId'] as int? ?? lineId,
          lineNumber: data['lineNumber'] as int? ?? 0,
          isAuthorized: data['authorized'] as bool? ?? true,
          operator: operator,
          authorizedAt: data['authorizedAt'] != null
              ? DateTime.tryParse(data['authorizedAt'] as String)
              : DateTime.now(),
        );
      },
    );
  }

  @override
  Future<BootstrapLineState> getLineState(int lineId) async {
    return await _apiClient.request<BootstrapLineState>(
      path: '/palletizing-line/lines/$lineId/state',
      method: 'GET',
      parser: (json) => BootstrapLineStateModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
  }) async {
    return await _apiClient.request<PalletCreateResponse>(
      path: '/palletizing-line/lines/$lineId/pallets',
      method: 'POST',
      data: {'productTypeId': productTypeId, 'quantity': quantity},
      parser: (json) => PalletCreateResponseModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<PrintAttemptResult> logLinePrintAttempt({
    required int lineId,
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  }) async {
    return await _apiClient.request<PrintAttemptResult>(
      path: '/palletizing-line/lines/$lineId/pallets/$palletId/print-attempts',
      method: 'POST',
      data: {
        'printerIdentifier': printerIdentifier,
        'status': status,
        'failureReason': ?failureReason,
      },
      parser: (json) => PrintAttemptResultModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<List<SessionTableRow>> switchProduct({
    required int lineId,
    required int previousProductTypeId,
    required int looseCount,
  }) async {
    return await _apiClient.requestList<SessionTableRow>(
      path: '/palletizing-line/lines/$lineId/product-switch',
      method: 'POST',
      data: {
        'previousProductTypeId': previousProductTypeId,
        'loosePackageCount': looseCount,
      },
      itemParser: (json) => SessionTableRowModel.fromJson(json),
    );
  }

  @override
  Future<LineHandoverInfo> createLineHandover(
    int lineId, {
    int? incompletePalletProductTypeId,
    int? incompletePalletQuantity,
    List<Map<String, dynamic>>? looseBalances,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (incompletePalletProductTypeId != null) {
      data['incompletePalletProductTypeId'] = incompletePalletProductTypeId;
    }
    if (incompletePalletQuantity != null) {
      data['incompletePalletQuantity'] = incompletePalletQuantity;
    }
    if (looseBalances != null && looseBalances.isNotEmpty) {
      data['looseBalances'] = looseBalances;
    }
    if (notes != null && notes.isNotEmpty) {
      data['notes'] = notes;
    }
    return await _apiClient.request<LineHandoverInfo>(
      path: '/palletizing-line/lines/$lineId/handover',
      method: 'POST',
      data: data,
      parser: (json) =>
          LineHandoverInfoModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<LineHandoverInfo?> getLineHandover(int lineId) async {
    try {
      final result = await _apiClient.request<LineHandoverInfo?>(
        path: '/palletizing-line/lines/$lineId/handover/pending',
        method: 'GET',
        parser: (json) {
          final data = json['data'];
          if (data == null) return null;
          return LineHandoverInfoModel.fromJson(data as Map<String, dynamic>);
        },
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LineHandoverInfo> confirmLineHandover({
    required int lineId,
    required int handoverId,
  }) async {
    return await _apiClient.request<LineHandoverInfo>(
      path: '/palletizing-line/lines/$lineId/handover/$handoverId/confirm',
      method: 'POST',
      data: {},
      parser: (json) =>
          LineHandoverInfoModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<LineHandoverInfo> rejectLineHandover({
    required int lineId,
    required int handoverId,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (notes != null && notes.isNotEmpty) {
      data['notes'] = notes;
    }
    return await _apiClient.request<LineHandoverInfo>(
      path: '/palletizing-line/lines/$lineId/handover/$handoverId/reject',
      method: 'POST',
      data: data,
      parser: (json) =>
          LineHandoverInfoModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<OpenItemsResponse> getOpenItems(int lineId) async {
    return await _apiClient.request<OpenItemsResponse>(
      path: '/palletizing-line/lines/$lineId/open-items',
      method: 'GET',
      parser: (json) =>
          OpenItemsResponseModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<ProducePalletFromLooseResponse> producePalletFromLoose({
    required int lineId,
    required int productTypeId,
    required int looseQuantityToUse,
    int freshQuantityToAdd = 0,
  }) async {
    return await _apiClient.request<ProducePalletFromLooseResponse>(
      path: '/palletizing-line/lines/$lineId/loose-balances/produce-pallet',
      method: 'POST',
      data: {
        'productTypeId': productTypeId,
        'looseQuantityToUse': looseQuantityToUse,
        'freshQuantityToAdd': freshQuantityToAdd,
      },
      parser: (json) => ProducePalletFromLooseResponseModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<CompleteIncompletePalletResponse> completeIncompletePallet({
    required int lineId,
    int additionalFreshQuantity = 0,
  }) async {
    return await _apiClient.request<CompleteIncompletePalletResponse>(
      path: '/palletizing-line/lines/$lineId/incomplete-pallet/complete',
      method: 'POST',
      data: {'additionalFreshQuantity': additionalFreshQuantity},
      parser: (json) => CompleteIncompletePalletResponseModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }
}
