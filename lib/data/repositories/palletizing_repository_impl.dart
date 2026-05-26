import 'package:flutter/foundation.dart';

import '../../domain/entities/bootstrap_response.dart';
import '../../domain/entities/falet_exists_response.dart';
import '../../domain/entities/falet_response.dart';
import '../../domain/entities/first_pallet_context.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/pallet_create_response.dart';
import '../../domain/entities/palletizer_auth_result.dart';
import '../../domain/entities/palletizer_session.dart';
import '../../domain/entities/print_attempt_result.dart';
import '../../domain/entities/session_production_detail.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/repositories/palletizing_repository.dart';
import '../../domain/entities/production_line.dart';
import '../datasources/api_client.dart';
import '../models/bootstrap_response_model.dart';
import '../models/falet_exists_response_model.dart';
import '../models/falet_response_model.dart';
import '../models/first_pallet_context_model.dart';
import '../models/operator_model.dart';
import '../models/pallet_create_response_model.dart';
import '../models/palletizer_session_model.dart';
import '../models/print_attempt_result_model.dart';
import '../models/product_type_model.dart';
import '../models/production_line_model.dart';
import '../models/session_production_detail_model.dart';

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
      parser: (json) {
        // Raw-shape diagnostic — ALWAYS-ON (not kDebugMode-gated) so release
        // APKs surface the actual wire shape in `adb logcat`. Never logs the
        // device key or any operator data. Confirms whether the parser sees
        // `data.lines` at all and which top-level keys the backend actually
        // returns, so a future schema rename never silently parses to zero
        // lines again.
        final topKeys = json.keys.toList();
        final dataRaw = json['data'];
        List<String> dataKeys = const [];
        int linesCount = 0;
        int? lineStatesCount;
        int prodLinesCount = 0;
        int prodTypesCount = 0;
        if (dataRaw is Map<String, dynamic>) {
          dataKeys = dataRaw.keys.toList();
          final l = dataRaw['lines'];
          if (l is List) linesCount = l.length;
          final ls = dataRaw['lineStates'];
          if (ls is List) lineStatesCount = ls.length;
          final pl = dataRaw['productionLines'];
          if (pl is List) prodLinesCount = pl.length;
          final pt = dataRaw['productTypes'];
          if (pt is List) prodTypesCount = pt.length;
        }
        debugPrint(
          '[Bootstrap RAW] topKeys=$topKeys '
          'data.exists=${dataRaw is Map} '
          'data.keys=$dataKeys '
          'data.lines=$linesCount '
          'data.lineStates=${lineStatesCount ?? "absent"} '
          'data.productionLines=$prodLinesCount '
          'data.productTypes=$prodTypesCount',
        );
        final data = json['data'];
        if (data is! Map<String, dynamic>) {
          throw StateError(
            'Bootstrap response missing top-level "data" object '
            '(got ${data.runtimeType}). Top-level keys: ${json.keys.toList()}',
          );
        }
        return BootstrapResponseModel.fromJson(data);
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
  Future<FirstPalletContext> getFirstPalletContext(int lineId) async {
    return await _apiClient.request<FirstPalletContext>(
      path: '/palletizing-line/lines/$lineId/first-pallet-context',
      method: 'GET',
      parser: (json) => FirstPalletContextModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
  }) async {
    return await _apiClient.request<PalletCreateResponse>(
      path: '/palletizing-line/lines/$lineId/pallets',
      method: 'POST',
      data: {
        'productTypeId': productTypeId,
        'quantity': quantity,
        'confirmOverproduction': confirmOverproduction,
      },
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

  // ── Palletizer auth (per-line) ──

  @override
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  }) async {
    return await _apiClient.request<PalletizerAuthResult>(
      path: '/palletizing-line/lines/$lineId/palletizer-auth',
      method: 'POST',
      data: {'pin': pin},
      parser: (json) => PalletizerAuthResultModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId) async {
    return await _apiClient.request<PalletizerSession>(
      path: '/palletizing-line/lines/$lineId/palletizer-session/current',
      method: 'GET',
      parser: (json) =>
          PalletizerSessionModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<void> palletizerLogout({
    required int lineId,
    required String sessionToken,
  }) async {
    await _apiClient.request<void>(
      path: '/palletizing-line/lines/$lineId/palletizer-logout',
      method: 'POST',
      data: {'sessionToken': sessionToken},
      parser: (_) {},
    );
  }

  @override
  Future<FaletResponse> getFaletItems(int lineId) async {
    return await _apiClient.request<FaletResponse>(
      path: '/palletizing-line/lines/$lineId/falet',
      method: 'GET',
      parser: (json) =>
          FaletResponseModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  @override
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId) async {
    return await _apiClient.request<SessionProductionDetail>(
      path: '/palletizing-line/lines/$lineId/session-production-detail',
      method: 'GET',
      parser: (json) => SessionProductionDetailModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  Future<FaletExistsResponse> checkFaletExists(int lineId) async {
    return await _apiClient.request<FaletExistsResponse>(
      path: '/palletizing-line/lines/$lineId/falet/exists',
      method: 'GET',
      parser: (json) => FaletExistsResponseModel.fromJson(
        json['data'] as Map<String, dynamic>,
      ),
    );
  }

}
