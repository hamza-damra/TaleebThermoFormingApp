import '../entities/bootstrap_response.dart';
import '../entities/falet_convert_to_pallet_response.dart';
import '../entities/falet_dispose_response.dart';
import '../entities/falet_response.dart';
import '../entities/line_authorization_state.dart';
import '../entities/line_handover_info.dart';
import '../entities/pallet_create_response.dart';
import '../entities/print_attempt_result.dart';
import '../entities/session_production_detail.dart';
import '../entities/session_table_row.dart';

abstract class PalletizingRepository {
  // ── Line-scoped endpoints (/palletizing-line) ──

  /// GET /palletizing-line/bootstrap
  Future<BootstrapResponse> bootstrap();

  /// POST /palletizing-line/lines/{lineId}/authorize-pin
  Future<LineAuthorizationState> authorizeLine({
    required int lineId,
    required String pin,
  });

  /// GET /palletizing-line/lines/{lineId}/state
  Future<BootstrapLineState> getLineState(int lineId);

  /// POST /palletizing-line/lines/{lineId}/pallets
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
  });

  /// POST /palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts
  Future<PrintAttemptResult> logLinePrintAttempt({
    required int lineId,
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  });

  /// POST /palletizing-line/lines/{lineId}/product-switch
  Future<List<SessionTableRow>> switchProduct({
    required int lineId,
    required int previousProductTypeId,
    required int looseCount,
  });

  /// POST /palletizing-line/lines/{lineId}/handover
  Future<LineHandoverInfo> createLineHandover(
    int lineId, {
    int? lastActiveProductTypeId,
    int? lastActiveProductFaletQuantity,
    String? notes,
  });

  /// GET /palletizing-line/lines/{lineId}/handover/pending
  Future<LineHandoverInfo?> getLineHandover(int lineId);

  /// POST /palletizing-line/lines/{lineId}/handover/{id}/confirm
  Future<LineHandoverInfo> confirmLineHandover({
    required int lineId,
    required int handoverId,
  });

  /// POST /palletizing-line/lines/{lineId}/handover/{id}/reject
  Future<LineHandoverInfo> rejectLineHandover({
    required int lineId,
    required int handoverId,
    String? notes,
  });

  /// GET /palletizing-line/lines/{lineId}/falet
  Future<FaletResponse> getFaletItems(int lineId);

  /// POST /palletizing-line/lines/{lineId}/falet/convert-to-pallet
  Future<FaletConvertToPalletResponse> convertFaletToPallet({
    required int lineId,
    required int faletId,
    int additionalFreshQuantity,
  });

  /// POST /palletizing-line/lines/{lineId}/falet/dispose
  Future<FaletDisposeResponse> disposeFalet({
    required int lineId,
    required int faletId,
    String? reason,
  });

  /// GET /palletizing-line/lines/{lineId}/session-production-detail
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId);
}
