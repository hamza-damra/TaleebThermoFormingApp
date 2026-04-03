import '../../domain/entities/bootstrap_response.dart';
import '../../domain/entities/line_authorization_state.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/print_attempt_result.dart';
import '../../domain/entities/session_table_row.dart';
import '../../domain/repositories/palletizing_repository.dart';
import '../datasources/api_client.dart';
import '../models/bootstrap_response_model.dart';
import '../models/line_handover_info_model.dart';
import '../models/operator_model.dart';
import '../models/pallet_create_response_model.dart';
import '../models/print_attempt_result_model.dart';
import '../models/session_table_row_model.dart';

class PalletizingRepositoryImpl implements PalletizingRepository {
  final ApiClient _apiClient;

  PalletizingRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  // ── Line-scoped endpoints (/palletizing-line) ──

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
    return await _apiClient.request<List<SessionTableRow>>(
      path: '/palletizing-line/lines/$lineId/product-switch',
      method: 'POST',
      data: {
        'previousProductTypeId': previousProductTypeId,
        'loosePackageCount': looseCount,
      },
      parser: (json) {
        final data = json['data'] as Map<String, dynamic>;
        final sessionTableJson = data['sessionTable'] as List<dynamic>? ?? [];
        return sessionTableJson
            .map((item) =>
                SessionTableRowModel.fromJson(item as Map<String, dynamic>))
            .toList();
      },
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
    final body = <String, dynamic>{};
    if (incompletePalletProductTypeId != null) {
      body['incompletePalletProductTypeId'] = incompletePalletProductTypeId;
    }
    if (incompletePalletQuantity != null) {
      body['incompletePalletQuantity'] = incompletePalletQuantity;
    }
    if (looseBalances != null && looseBalances.isNotEmpty) {
      body['looseBalances'] = looseBalances;
    }
    if (notes != null && notes.isNotEmpty) {
      body['notes'] = notes;
    }
    return await _apiClient.request<LineHandoverInfo>(
      path: '/palletizing-line/lines/$lineId/handover',
      method: 'POST',
      data: body,
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
    final body = <String, dynamic>{};
    if (notes != null && notes.isNotEmpty) {
      body['notes'] = notes;
    }
    return await _apiClient.request<LineHandoverInfo>(
      path: '/palletizing-line/lines/$lineId/handover/$handoverId/reject',
      method: 'POST',
      data: body,
      parser: (json) =>
          LineHandoverInfoModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}
