import '../entities/bootstrap_response.dart';
import '../entities/falet_convert_to_pallet_response.dart';
import '../entities/falet_exists_response.dart';
import '../entities/falet_dispose_response.dart';
import '../entities/falet_resolution_entry.dart';
import '../entities/falet_response.dart';
import '../entities/first_pallet_suggestion.dart';
import '../entities/line_handover_info.dart';
import '../entities/pallet_create_response.dart';
import '../entities/palletizer_auth_result.dart';
import '../entities/palletizer_session.dart';
import '../entities/print_attempt_result.dart';
import '../entities/session_production_detail.dart';

abstract class PalletizingRepository {
  // ── Line-scoped endpoints (/palletizing-line) ──

  /// GET /palletizing-line/bootstrap
  Future<BootstrapResponse> bootstrap();

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

  // ── Palletizer auth (per-line) ──

  /// POST /palletizing-line/lines/{lineId}/palletizer-auth
  /// Returns the new session plus the raw sessionToken (only ever exposed once).
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  });

  /// GET /palletizing-line/lines/{lineId}/palletizer-session/current
  /// Throws ApiException(code: PALLETIZER_SESSION_REQUIRED) when no active session.
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId);

  /// POST /palletizing-line/lines/{lineId}/palletizer-logout
  /// Idempotent — already-ended sessions return 200/no-op.
  Future<void> palletizerLogout({
    required int lineId,
    required String sessionToken,
  });

  /// POST /palletizing-line/lines/{lineId}/handover
  Future<LineHandoverInfo> createLineHandover(
    int lineId, {
    int? lastActiveProductTypeId,
    int? lastActiveProductFaletQuantity,
    String? notes,
    List<FaletResolutionEntry>? faletResolutions,
  });

  /// GET /palletizing-line/lines/{lineId}/handover/pending
  Future<LineHandoverInfo?> getLineHandover(int lineId);

  /// POST /palletizing-line/lines/{lineId}/handover/{id}/confirm
  Future<LineHandoverInfo> confirmLineHandover({
    required int lineId,
    required int handoverId,
    String? receiptNotes,
  });

  /// POST /palletizing-line/lines/{lineId}/handover/{id}/reject
  Future<LineHandoverInfo> rejectLineHandover({
    required int lineId,
    required int handoverId,
    required bool incorrectQuantity,
    required bool otherReason,
    String? otherReasonNotes,
    List<Map<String, dynamic>>? itemObservations,
    bool undeclaredFaletFound = false,
    int? undeclaredFaletObservedQuantity,
    String? undeclaredFaletNotes,
  });

  /// GET /palletizing-line/lines/{lineId}/falet
  Future<FaletResponse> getFaletItems(int lineId);

  /// GET /palletizing-line/lines/{lineId}/falet/first-pallet-suggestion
  Future<FirstPalletSuggestion> getFirstPalletSuggestion(int lineId);

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

  /// GET /palletizing-line/lines/{lineId}/falet/exists
  Future<FaletExistsResponse> checkFaletExists(int lineId);
}
