// Shared fakes + fixtures for the LINE_3 (N-line) provider and screen tests.
//
// Fixtures are deliberately **skewed**: backend lineIds 11 / 12 / 13 carry
// lineNumbers 1 / 2 / 3, and SSE frames may carry unrelated
// thermoformingLineIds. Any code that confuses lineId, lineNumber or a
// thermoforming id fails these tests — on production lines 1 and 2 the ids
// happen to match, which hides exactly that class of bug.

import 'dart:async';

import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/takeover_notification_service.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_exists_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_response.dart';
import 'package:taleeb_thermoforming/domain/entities/first_pallet_context.dart';
import 'package:taleeb_thermoforming/domain/entities/manager_announcement.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_session.dart';
import 'package:taleeb_thermoforming/domain/entities/plan_item_close_request.dart';
import 'package:taleeb_thermoforming/domain/entities/print_attempt_result.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/takeover_request.dart';
import 'package:taleeb_thermoforming/domain/repositories/palletizing_repository.dart';

/// Backend lineId for each lineNumber in the skewed fixtures.
const lineIdForNumber = {1: 11, 2: 12, 3: 13};

const abjadLabels = {1: 'خط أ', 2: 'خط ب', 3: 'خط ج'};

class CreateCall {
  final int lineId;
  final int productTypeId;
  final int quantity;
  final int expectedPlanItemId;
  final bool confirmOverproduction;
  final String? grindingRecommendationReason;

  const CreateCall({
    required this.lineId,
    required this.productTypeId,
    required this.quantity,
    required this.expectedPlanItemId,
    required this.confirmOverproduction,
    this.grindingRecommendationReason,
  });
}

/// One call to a plan-item close-request endpoint.
class CloseRequestCall {
  final int lineId;
  final int? closeRequestId;
  final String sessionToken;

  const CloseRequestCall({
    required this.lineId,
    required this.sessionToken,
    this.closeRequestId,
  });
}

class FakePalletizingRepository implements PalletizingRepository {
  BootstrapResponse Function()? bootstrapFn;

  /// When it returns a future, bootstrap completes with it — lets a test hold
  /// a bootstrap in flight. Checked before [bootstrapFn].
  Future<BootstrapResponse>? Function()? bootstrapAsyncFn;

  /// Serves `/session-production-detail`; unset → [UnimplementedError].
  Future<SessionProductionDetail> Function(int lineId)? sessionDetailFn;
  final List<int> sessionDetailLineIds = [];
  BootstrapLineState Function(int lineId)? lineStateFn;

  /// When it returns a future for a line, `/state` for that line completes
  /// with it — lets a test control completion order. Checked before
  /// [lineStateFn].
  Future<BootstrapLineState>? Function(int lineId)? lineStateAsyncFn;
  PalletizerSession? Function(int lineId)? sessionFn;
  Object? createPalletError;
  PalletCreateResponse Function(CreateCall call)? createSuccessFn;

  int bootstrapCalls = 0;
  final List<int> lineStateLineIds = [];
  final List<int> sessionLineIds = [];
  final List<int> announcementLineIds = [];
  final List<CreateCall> createCalls = [];

  // ── Plan-item close handshake ──

  /// The backend's active request per lineId — what the pending read serves.
  /// The default decision handlers below mutate it like the backend does.
  final Map<int, PlanItemCloseRequest> activeCloseRequests = {};

  /// Thrown by every pending read for that line while present.
  final Map<int, Object> closeRequestReadErrors = {};

  /// When set, a pending read captures the backend state immediately but
  /// answers only once this completes — a slow, soon-to-be-stale response.
  Completer<void>? readGate;

  /// Queued decision results, consumed one per call: a
  /// [PlanItemCloseRequest] is returned, anything else is thrown. When empty
  /// the default handler simulates a successful backend decision.
  final List<Object> morePalletsResults = [];
  final List<Object> confirmResults = [];

  /// When set, every decision waits for it before answering.
  Completer<void>? decisionGate;

  final List<CloseRequestCall> closeRequestReads = [];
  final List<CloseRequestCall> morePalletsCalls = [];
  final List<CloseRequestCall> confirmCalls = [];

  @override
  Future<BootstrapResponse> bootstrap() async {
    bootstrapCalls++;
    final pending = bootstrapAsyncFn?.call();
    if (pending != null) return pending;
    final fn = bootstrapFn;
    if (fn == null) throw StateError('bootstrapFn not configured');
    return fn();
  }

  @override
  Future<BootstrapLineState> getLineState(int lineId) async {
    lineStateLineIds.add(lineId);
    final pending = lineStateAsyncFn?.call(lineId);
    if (pending != null) return pending;
    final fn = lineStateFn;
    if (fn == null) throw StateError('lineStateFn not configured');
    return fn(lineId);
  }

  @override
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId) async {
    sessionLineIds.add(lineId);
    final session = sessionFn?.call(lineId);
    if (session == null) {
      throw ApiException(code: 'PALLETIZER_SESSION_REQUIRED', message: 'none');
    }
    return session;
  }

  @override
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    required int expectedPlanItemId,
    bool confirmOverproduction = false,
    int? firstPalletFaletExpectedQuantity,
    int? firstPalletFaletId,
    String? grindingRecommendationReason,
  }) async {
    final call = CreateCall(
      lineId: lineId,
      productTypeId: productTypeId,
      quantity: quantity,
      expectedPlanItemId: expectedPlanItemId,
      confirmOverproduction: confirmOverproduction,
      grindingRecommendationReason: grindingRecommendationReason,
    );
    createCalls.add(call);
    final err = createPalletError;
    if (err != null) throw err;
    final ok = createSuccessFn;
    if (ok == null) throw UnimplementedError('createSuccessFn not configured');
    return ok(call);
  }

  @override
  Future<List<ManagerAnnouncement>> getPendingUrgentAnnouncements(
    int lineId,
  ) async {
    announcementLineIds.add(lineId);
    return const [];
  }

  @override
  Future<void> ackUrgentAnnouncement({
    required int announcementId,
    required int lineId,
  }) async {}

  /// Configures `palletizerAuth`; unset → [UnimplementedError].
  PalletizerAuthResult Function(int lineId)? authFn;

  @override
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  }) async {
    final fn = authFn;
    if (fn == null) throw UnimplementedError('authFn not configured');
    return fn(lineId);
  }

  @override
  Future<FirstPalletContext> getFirstPalletContext(int lineId) =>
      throw UnimplementedError();

  @override
  Future<PrintAttemptResult> logLinePrintAttempt({
    required int lineId,
    required int palletId,
    required String printerIdentifier,
    required String status,
    String? failureReason,
  }) => throw UnimplementedError();

  @override
  Future<void> palletizerLogout({
    required int lineId,
    required String sessionToken,
  }) async {}

  @override
  Future<FaletResponse> getFaletItems(int lineId) => throw UnimplementedError();

  @override
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId) {
    sessionDetailLineIds.add(lineId);
    final fn = sessionDetailFn;
    if (fn == null) throw UnimplementedError('sessionDetailFn not configured');
    return fn(lineId);
  }

  @override
  Future<FaletExistsResponse> checkFaletExists(int lineId) =>
      throw UnimplementedError();

  @override
  Future<PalletLabel> fetchPalletLabel(String scannedValue) =>
      throw UnimplementedError();

  @override
  Future<PlanItemCloseRequest?> getActivePlanItemCloseRequest({
    required int lineId,
    required String sessionToken,
  }) async {
    closeRequestReads.add(
      CloseRequestCall(lineId: lineId, sessionToken: sessionToken),
    );
    final error = closeRequestReadErrors[lineId];
    if (error != null) throw error;
    final snapshot = activeCloseRequests[lineId];
    final gate = readGate;
    if (gate != null) await gate.future;
    return snapshot;
  }

  @override
  Future<PlanItemCloseRequest> reportMorePalletsRemain({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  }) async {
    morePalletsCalls.add(
      CloseRequestCall(
        lineId: lineId,
        closeRequestId: closeRequestId,
        sessionToken: sessionToken,
      ),
    );
    await decisionGate?.future;
    if (morePalletsResults.isNotEmpty) {
      return _answer(morePalletsResults.removeAt(0));
    }
    final active = _requireActive(lineId, closeRequestId);
    final next = closeRequest(
      id: closeRequestId,
      lineId: lineId,
      planItemId: active.productionPlanItemId,
      status: PlanItemCloseRequestStatus.palletizerCompletingPallets,
    );
    activeCloseRequests[lineId] = next;
    return next;
  }

  @override
  Future<PlanItemCloseRequest> confirmAllPalletsRegistered({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  }) async {
    confirmCalls.add(
      CloseRequestCall(
        lineId: lineId,
        closeRequestId: closeRequestId,
        sessionToken: sessionToken,
      ),
    );
    await decisionGate?.future;
    if (confirmResults.isNotEmpty) {
      return _answer(confirmResults.removeAt(0));
    }
    final active = _requireActive(lineId, closeRequestId);
    activeCloseRequests.remove(lineId);
    return closeRequest(
      id: closeRequestId,
      lineId: lineId,
      planItemId: active.productionPlanItemId,
      status: PlanItemCloseRequestStatus.confirmed,
    );
  }

  PlanItemCloseRequest _requireActive(int lineId, int closeRequestId) {
    final active = activeCloseRequests[lineId];
    if (active == null || active.closeRequestId != closeRequestId) {
      throw ApiException(
        code: 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_NOT_ACTIVE',
        message: 'not active',
        statusCode: 409,
      );
    }
    return active;
  }

  static PlanItemCloseRequest _answer(Object result) {
    if (result is PlanItemCloseRequest) return result;
    throw result;
  }
}

/// An ACTIVE palletizer session on [lineId].
PalletizerSession activeSession(int lineId) => PalletizerSession(
  sessionId: 500 + lineId,
  palletizerOperatorId: 70,
  palletizerName: 'أحمد خالد',
  palletizingLineId: lineId,
  palletizingLineName: 'line $lineId',
);

/// A close request as the backend returns it, for line [lineId].
PlanItemCloseRequest closeRequest({
  int id = 3021,
  required int lineId,
  int planItemId = 912,
  PlanItemCloseRequestStatus status =
      PlanItemCloseRequestStatus.waitingForPalletizerDecision,
  bool alreadyProcessed = false,
}) => PlanItemCloseRequest(
  closeRequestId: id,
  status: status,
  productionPlanItemId: planItemId,
  palletizingLineId: lineId,
  productTypeId: 31,
  productTypeName: 'علبة 500 مل شفاف',
  targetPackageQuantity: 2000,
  producedPackageQuantity: 1840,
  thermoformingLineId: 4,
  requestedByOperatorName: 'محمد أحمد',
  alreadyProcessed: alreadyProcessed,
);

class FakeAuthStorage extends AuthLocalStorage {
  final Map<int, String> tokens = {};

  @override
  Future<void> savePalletizerSessionToken(int lineId, String token) async {
    tokens[lineId] = token;
  }

  @override
  Future<String?> getPalletizerSessionToken(int lineId) async => tokens[lineId];

  @override
  Future<void> clearPalletizerSessionToken(int lineId) async {
    tokens.remove(lineId);
  }
}

class FakeNotifications extends TakeoverNotificationService {
  int alertCalls = 0;

  @override
  Future<void> alert() async {
    alertCalls++;
  }

  @override
  void dispose() {}
}

/// A line state for [lineNumber] in the skewed fixtures. `lineName` and
/// `lineDisplayName` default to the server's abjad label.
BootstrapLineState skewedLine(
  int lineNumber, {
  bool authorized = true,
  bool waitingForOperator = false,
  String? lineName,
  String? lineDisplayName,
  int? planItemId,
  int? planProductId,
  TakeoverRequest? takeover,
}) {
  final label = abjadLabels[lineNumber] ?? 'خط $lineNumber';
  return BootstrapLineState(
    lineId: lineIdForNumber[lineNumber]!,
    lineNumber: lineNumber,
    lineName: lineName ?? label,
    lineDisplayName: lineDisplayName ?? label,
    isAuthorized: authorized && !waitingForOperator,
    authorizedOperator: authorized && !waitingForOperator
        ? Operator(id: lineNumber, name: 'Operator $lineNumber')
        : null,
    lineUiMode: authorized && !waitingForOperator
        ? 'AUTHORIZED'
        : 'NEEDS_AUTHORIZATION',
    waitingForOperator: waitingForOperator,
    waitingForOperatorMessageTitle: waitingForOperator
        ? 'بانتظار استلام الخط'
        : null,
    currentPlanItemId: planItemId,
    currentPlanItemProductTypeId: planProductId,
    currentPlanItemProductName: planProductId == null ? null : 'Plan product',
    pendingTakeoverRequest: takeover,
    takeoverRequestStatus: takeover == null ? null : 'PENDING',
  );
}

BootstrapResponse skewedBootstrap(List<BootstrapLineState> lines) =>
    BootstrapResponse(productTypes: const [], lines: lines);
