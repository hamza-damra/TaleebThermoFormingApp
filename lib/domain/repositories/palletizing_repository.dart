import '../entities/biometric_login.dart';
import '../entities/bootstrap_response.dart';
import '../entities/pallet_label.dart';
import '../entities/falet_exists_response.dart';
import '../entities/falet_response.dart';
import '../entities/first_pallet_context.dart';
import '../entities/manager_announcement.dart';
import '../entities/pallet_create_response.dart';
import '../entities/palletizer_auth_result.dart';
import '../entities/palletizer_session.dart';
import '../entities/plan_item_close_request.dart';
import '../entities/print_attempt_result.dart';
import '../entities/production_transit.dart';
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
  /// [expectedPlanItemId] (V190, mandatory) is the line's `currentPlanItemId`
  /// the worker saw. A mismatch returns `PRODUCTION_PLAN_CURRENT_ITEM_CHANGED`
  /// with nothing created — callers must never auto-retry with a new id.
  ///
  /// When [firstPalletFaletExpectedQuantity] is non-null, the backend deducts
  /// exactly that quantity from the matching open FALET row in the same
  /// transaction as pallet creation and surfaces a `faletConsumption` block
  /// on the response. Optional [firstPalletFaletId] binds the consumption to
  /// a specific FALET row; null means "the matching open FALET for this
  /// product on this line".
  ///
  /// When [grindingRecommendationReason] is non-null the request carries
  /// `grindingRecommendation: {reason}`: the backend creates the pallet and,
  /// in the same transaction, a grinding order awaiting the plant manager's
  /// approval (response `grindingOrder`). Null = a normal pallet.
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    required int expectedPlanItemId,
    bool confirmOverproduction = false,
    int? firstPalletFaletExpectedQuantity,
    int? firstPalletFaletId,
    String? grindingRecommendationReason,
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
  /// Throws [BiometricDenialException] when the biometric login gate refuses
  /// the login (a `BIOMETRIC_*` 403) — a fingerprint is needed, not a new PIN.
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

  // ── Plan-item close handshake (V190) ──
  // All three calls send the palletizer's PIN-issued session token in the
  // `X-Palletizer-Session-Token` header; the backend takes the confirming
  // palletizer's identity from that session only. 401/403
  // `PALLETIZER_SESSION_REQUIRED` means the token is missing, ended, or
  // belongs to another line.

  /// GET /palletizing-line/lines/{lineId}/plan-item-close-request
  ///
  /// The authoritative "is an item close waiting on this line?" read. Returns
  /// `null` when there is no active request.
  Future<PlanItemCloseRequest?> getActivePlanItemCloseRequest({
    required int lineId,
    required String sessionToken,
  });

  /// POST /palletizing-line/lines/{lineId}/plan-item-close-requests/{closeRequestId}/more-pallets-remain
  ///
  /// "لا، بقيت طبليات للتسجيل". No body. Idempotent — a retry returns
  /// `alreadyProcessed: true`.
  Future<PlanItemCloseRequest> reportMorePalletsRemain({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  });

  /// POST /palletizing-line/lines/{lineId}/plan-item-close-requests/{closeRequestId}/confirm-all-pallets-registered
  ///
  /// "نعم، تم تسجيل جميع الطبليات". No body. Closes the item exactly once; a
  /// retry by the same session returns `alreadyProcessed: true`.
  Future<PlanItemCloseRequest> confirmAllPalletsRegistered({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  });

  // ── PRODUCTION → TRANSIT move (V210) ──
  // Both calls send a palletizer session token in `X-Palletizer-Session-Token`;
  // the scope is every line the token's employee holds an ACTIVE session on.
  // 401 `PALLETIZER_SESSION_REQUIRED` means that token is no longer usable.

  /// POST /palletizing-line/palletizer/pallets/move-to-transit
  ///
  /// [clientRequestId] is one UUID per physical scan, reused verbatim for
  /// every retry of that scan — a retry never makes a second movement
  /// (`replayed: true`).
  Future<PalletizerTransitMoveResult> movePalletToTransit({
    required String sessionToken,
    required String identifier,
    required String clientRequestId,
    required PalletTransitScanType scanType,
  });

  /// GET /palletizing-line/palletizer/production-pending-pallets
  Future<ProductionPendingPallets> getProductionPendingPallets({
    required String sessionToken,
  });

  // ── Sanitized urgent manager announcements ──

  /// GET /palletizing-line/urgent-announcements/pending?lineId={lineId}
  ///
  /// Returns the sanitized generic notices that are active, not expired, and
  /// not yet acknowledged by [lineId] (oldest first). The DTO carries no real
  /// message body or sender. See
  /// [docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md].
  Future<List<ManagerAnnouncement>> getPendingUrgentAnnouncements(int lineId);

  /// POST /palletizing-line/urgent-announcements/{announcementId}/ack?lineId={lineId}
  ///
  /// Acknowledges the announcement for [lineId]. Idempotent — a duplicate ack
  /// returns success. The backend forces `GENERIC_NOTICE_ACK`, keyed per line.
  Future<void> ackUrgentAnnouncement({
    required int announcementId,
    required int lineId,
  });

  // ── Pallet label reprint (unscoped — any shift / any line) ──

  /// GET /palletizing-line/pallets/{scannedValue}/label
  ///
  /// Resolves any pallet by its printed 12-digit number and returns the label
  /// payload for reprinting. Not scoped to a line, session, or shift.
  /// Throws ApiException with code `PALLET_LABEL_REPRINT_NOT_AVAILABLE` (409)
  /// when the pallet is cancelled, and `PALLET_BLOCKED_BY_GRINDING` (409) when
  /// its grinding started or finished.
  Future<PalletLabel> fetchPalletLabel(String scannedValue);
}
