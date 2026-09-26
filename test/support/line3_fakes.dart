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
import 'package:taleeb_thermoforming/domain/entities/production_transit.dart';
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

  /// When it returns a future, `palletizerAuth` completes with it — lets a
  /// test hold a login in flight. Checked before [authFn].
  Future<PalletizerAuthResult>? Function(int lineId)? authAsyncFn;

  /// Every `palletizerAuth` call, in order.
  final List<({int lineId, String pin})> authCalls = [];

  @override
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  }) async {
    authCalls.add((lineId: lineId, pin: pin));
    final pending = authAsyncFn?.call(lineId);
    if (pending != null) return pending;
    final fn = authFn;
    if (fn == null) throw UnimplementedError('authFn not configured');
    return fn(lineId);
  }

  /// Serves `/first-pallet-context`; unset → [UnimplementedError].
  FirstPalletContext Function(int lineId)? firstPalletContextFn;

  @override
  Future<FirstPalletContext> getFirstPalletContext(int lineId) async {
    final fn = firstPalletContextFn;
    if (fn == null) throw UnimplementedError('firstPalletContextFn');
    return fn(lineId);
  }

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
  }) async {
    logoutLineIds.add(lineId);
    final error = logoutErrors[lineId];
    if (error != null) throw error;
  }

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

  // ── PRODUCTION → TRANSIT (V210) ──

  /// Pending list served per session token; unset → empty.
  ProductionPendingPallets Function(String sessionToken)? pendingFn;
  final List<String> pendingTokens = [];

  /// Queued move results, consumed one per call: a
  /// [PalletizerTransitMoveResult] is returned, anything else is thrown.
  /// When empty, [moveFn] answers (default: a fresh successful move).
  final List<Object> moveResults = [];
  PalletizerTransitMoveResult Function(TransitMoveCall call)? moveFn;
  final List<TransitMoveCall> moveCalls = [];

  /// When set, every move waits for it before answering.
  Completer<void>? moveGate;

  /// Logout errors per line (thrown by `palletizerLogout`).
  final Map<int, Object> logoutErrors = {};
  final List<int> logoutLineIds = [];

  @override
  Future<PalletizerTransitMoveResult> movePalletToTransit({
    required String sessionToken,
    required String identifier,
    required String clientRequestId,
    required PalletTransitScanType scanType,
  }) async {
    final call = TransitMoveCall(
      sessionToken: sessionToken,
      identifier: identifier,
      clientRequestId: clientRequestId,
      scanType: scanType,
    );
    moveCalls.add(call);
    await moveGate?.future;
    if (moveResults.isNotEmpty) {
      final next = moveResults.removeAt(0);
      if (next is PalletizerTransitMoveResult) return next;
      throw next;
    }
    // Like the backend: the response carries the canonical 12 digits.
    return (moveFn ??
        (c) => transitMoveResult(PalletIdentifier.canonicalize(c.identifier)))(
      call,
    );
  }

  @override
  Future<ProductionPendingPallets> getProductionPendingPallets({
    required String sessionToken,
  }) async {
    pendingTokens.add(sessionToken);
    return pendingFn?.call(sessionToken) ?? ProductionPendingPallets.empty;
  }

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

/// One call to the move-to-transit endpoint.
class TransitMoveCall {
  final String sessionToken;
  final String identifier;
  final String clientRequestId;
  final PalletTransitScanType scanType;

  const TransitMoveCall({
    required this.sessionToken,
    required this.identifier,
    required this.clientRequestId,
    required this.scanType,
  });
}

/// A successful move of [identifier] as the backend returns it.
PalletizerTransitMoveResult transitMoveResult(
  String identifier, {
  int palletId = 55012,
  bool replayed = false,
  bool movementUndone = false,
  bool inherited = false,
  int lineId = 11,
}) => PalletizerTransitMoveResult(
  movementId: 90211,
  palletId: palletId,
  scannedValue: identifier,
  productTypeId: 7,
  productTypeName: 'علبة 500 مل',
  palletizingLineId: lineId,
  palletizingLineName: 'خط أ',
  thermoformingShiftLineId: 3120,
  fromLocation: 'PRODUCTION',
  toLocation: 'TRANSIT',
  currentLocation: movementUndone ? 'PRODUCTION' : 'TRANSIT',
  movedAt: DateTime.utc(2026, 9, 24, 12, 3, 11),
  movedAtDisplay: '2026-09-24، 03:03 مساءً',
  movedByName: 'أحمد',
  producedByPalletizerName: 'محمد',
  inherited: inherited,
  replayed: replayed,
  movementUndone: movementUndone,
);

/// A pallet still at PRODUCTION.
ProductionPendingPallet pendingPallet(
  String scannedValue, {
  int palletId = 55011,
  bool inherited = false,
}) => ProductionPendingPallet(
  palletId: palletId,
  scannedValue: scannedValue,
  productTypeId: 7,
  productTypeName: 'علبة 500 مل',
  thermoformingShiftLineId: 3120,
  currentLocation: 'PRODUCTION',
  producedAt: DateTime.utc(2026, 9, 24, 11, 40),
  producedAtDisplay: '2026-09-24، 02:40 مساءً',
  palletizerName: 'محمد',
  inherited: inherited,
);

/// The pending list of one employee's lines.
ProductionPendingPallets pendingList(
  Map<int, List<ProductionPendingPallet>> palletsByLine,
) {
  final lines = [
    for (final entry in palletsByLine.entries)
      ProductionPendingLine(
        palletizerSessionId: 500 + entry.key,
        palletizingLineId: entry.key,
        palletizingLineName: 'line ${entry.key}',
        thermoformingShiftLineId: 3120,
        pendingCount: entry.value.length,
        pallets: entry.value,
      ),
  ];
  return ProductionPendingPallets(
    totalPendingCount: lines.fold(0, (sum, l) => sum + l.pendingCount),
    lines: lines,
  );
}

/// An ACTIVE palletizer session on [lineId], for employee [operatorId].
PalletizerSession activeSession(int lineId, {int operatorId = 70}) =>
    PalletizerSession(
      sessionId: 500 + lineId,
      palletizerOperatorId: operatorId,
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
  int? packagesPerPallet,
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
    currentPlanItemPackagesPerPallet: packagesPerPallet,
    pendingTakeoverRequest: takeover,
    takeoverRequestStatus: takeover == null ? null : 'PENDING',
  );
}

BootstrapResponse skewedBootstrap(List<BootstrapLineState> lines) =>
    BootstrapResponse(productTypes: const [], lines: lines);
