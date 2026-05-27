import '../entities/bootstrap_response.dart';
import '../entities/falet_exists_response.dart';
import '../entities/falet_response.dart';
import '../entities/first_pallet_context.dart';
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

  /// GET /palletizing-line/lines/{lineId}/first-pallet-context
  /// Tells the app whether to open the include-FALET suggestion dialog before
  /// the user submits the normal POST /pallets call.
  Future<FirstPalletContext> getFirstPalletContext(int lineId);

  /// POST /palletizing-line/lines/{lineId}/pallets
  ///
  /// Production-plan enforcement (V81): [productTypeId] MUST be the line's
  /// current plan-item product id; the backend rejects anything else with
  /// `PRODUCTION_PLAN_PRODUCT_MISMATCH`. Pass [confirmOverproduction] = true
  /// only when re-sending the same request after the backend returned
  /// `PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED` and the operator
  /// confirmed the warning dialog.
  ///
  /// When [firstPalletFaletExpectedQuantity] is non-null, the backend deducts
  /// exactly that quantity from the matching open FALET row in the same
  /// transaction as pallet creation and surfaces a `faletConsumption` block
  /// on the response. Optional [firstPalletFaletId] binds the consumption to
  /// a specific FALET row; null means "the matching open FALET for this
  /// product on this line".
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
    int? firstPalletFaletExpectedQuantity,
    int? firstPalletFaletId,
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

  /// GET /palletizing-line/lines/{lineId}/falet
  Future<FaletResponse> getFaletItems(int lineId);

  /// GET /palletizing-line/lines/{lineId}/session-production-detail
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId);

  /// GET /palletizing-line/lines/{lineId}/falet/exists
  Future<FaletExistsResponse> checkFaletExists(int lineId);
}
