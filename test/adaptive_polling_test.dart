// Adaptive polling / state-refresh tests for the Pallet Worker App.
//
// REST stays the source of truth; SSE is only a refresh trigger and the
// polling *cadence* adapts to the SSE connection state and the line state.
// These tests exercise the cadence logic, the `/palletizer-session/current`
// gate, and stale-action recovery entirely at the [PalletizingProvider] level
// — no widgets, no platform plugins — so they run fast and deterministically.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/core/services/takeover_notification_service.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_exists_response.dart';
import 'package:taleeb_thermoforming/domain/entities/falet_response.dart';
import 'package:taleeb_thermoforming/domain/entities/first_pallet_context.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_session.dart';
import 'package:taleeb_thermoforming/domain/entities/plan_item_close_request.dart';
import 'package:taleeb_thermoforming/domain/entities/print_attempt_result.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/takeover_request.dart';
import 'package:taleeb_thermoforming/domain/entities/takeover_status.dart';
import 'package:taleeb_thermoforming/domain/entities/manager_announcement.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';
import 'package:taleeb_thermoforming/domain/entities/production_transit.dart';
import 'package:taleeb_thermoforming/domain/repositories/palletizing_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

// ─────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────

/// Fake repository. Behaviour is configured per test via the `*Fn` hooks; the
/// counters let tests assert that a stale action triggered a state refresh and
/// that `/palletizer-session/current` is only called when allowed.
class _FakeRepo implements PalletizingRepository {
  BootstrapResponse Function()? bootstrapFn;
  BootstrapLineState Function(int lineId)? lineStateFn;

  /// Async variant of [lineStateFn]. When set, `getLineState` returns this
  /// future, letting a test control completion order to exercise out-of-order
  /// `/state` responses. Takes precedence over [lineStateFn].
  Future<BootstrapLineState> Function(int lineId)? lineStateAsyncFn;

  /// Returns the active session for a line id, or `null` to make the backend
  /// answer with `PALLETIZER_SESSION_REQUIRED`.
  PalletizerSession? Function(int lineId)? sessionFn;

  /// Configures the response of `palletizerAuth`.
  PalletizerAuthResult Function(int lineId)? authFn;

  /// When set, `createLinePallet` throws this instead of succeeding.
  Object? createPalletError;

  int bootstrapCalls = 0;
  int lineStateCalls = 0;
  int createCalls = 0;

  /// Number of `/palletizer-session/current` calls — the spam counter.
  int sessionCalls = 0;
  final List<int> lineStateLineIds = [];

  @override
  Future<BootstrapResponse> bootstrap() async {
    bootstrapCalls++;
    final fn = bootstrapFn;
    if (fn == null) throw StateError('bootstrapFn not configured');
    return fn();
  }

  @override
  Future<BootstrapLineState> getLineState(int lineId) async {
    lineStateCalls++;
    lineStateLineIds.add(lineId);
    final asyncFn = lineStateAsyncFn;
    if (asyncFn != null) return asyncFn(lineId);
    final fn = lineStateFn;
    if (fn == null) throw StateError('lineStateFn not configured');
    return fn(lineId);
  }

  @override
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId) async {
    sessionCalls++;
    final session = sessionFn?.call(lineId);
    if (session == null) {
      throw ApiException(
        code: 'PALLETIZER_SESSION_REQUIRED',
        message: 'no session',
      );
    }
    return session;
  }

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
    createCalls++;
    final err = createPalletError;
    if (err != null) throw err;
    throw UnimplementedError('createLinePallet success path unused');
  }

  // ── Endpoints not exercised by these tests ──
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
  Future<SessionProductionDetail> getSessionProductionDetail(int lineId) =>
      throw UnimplementedError();

  @override
  Future<FaletExistsResponse> checkFaletExists(int lineId) =>
      throw UnimplementedError();

  @override
  Future<List<ManagerAnnouncement>> getPendingUrgentAnnouncements(int lineId) =>
      throw UnimplementedError();

  @override
  Future<void> ackUrgentAnnouncement({
    required int announcementId,
    required int lineId,
  }) =>
      throw UnimplementedError();

  @override
  Future<PalletLabel> fetchPalletLabel(String scannedValue) =>
      throw UnimplementedError();

  @override
  Future<PalletizerTransitMoveResult> movePalletToTransit({
    required String sessionToken,
    required String identifier,
    required String clientRequestId,
    required PalletTransitScanType scanType,
  }) => throw UnimplementedError();

  @override
  Future<ProductionPendingPallets> getProductionPendingPallets({
    required String sessionToken,
  }) async => ProductionPendingPallets.empty;

  @override
  Future<PlanItemCloseRequest?> getActivePlanItemCloseRequest({
    required int lineId,
    required String sessionToken,
  }) async => null;

  @override
  Future<PlanItemCloseRequest> reportMorePalletsRemain({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  }) => throw UnimplementedError();

  @override
  Future<PlanItemCloseRequest> confirmAllPalletsRegistered({
    required int lineId,
    required int closeRequestId,
    required String sessionToken,
  }) => throw UnimplementedError();
}

/// In-memory [AuthLocalStorage] — never touches `flutter_secure_storage`.
class _FakeAuthStorage extends AuthLocalStorage {
  final Map<int, String> _tokens = {};

  /// Pre-seeds a session token (simulates a prior palletizer login) so the
  /// `/palletizer-session/current` gate is open for the line.
  void seedToken(int lineId) => _tokens[lineId] = 'seeded-token';

  @override
  Future<void> savePalletizerSessionToken(int lineId, String token) async {
    _tokens[lineId] = token;
  }

  @override
  Future<String?> getPalletizerSessionToken(int lineId) async =>
      _tokens[lineId];

  @override
  Future<void> clearPalletizerSessionToken(int lineId) async {
    _tokens.remove(lineId);
  }
}

/// Silent notifications — no audio player, no vibration.
class _FakeNotifications extends TakeoverNotificationService {
  int alertCalls = 0;

  @override
  Future<void> alert() async {
    alertCalls++;
  }

  @override
  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────
// Builders
// ─────────────────────────────────────────────────────────────────────────

const _lineIdFor = {1: 101, 2: 102};

BootstrapLineState _line(
  int lineNumber, {
  bool authorized = true,
  bool withOperator = true,
  String? blockedReason,
  bool blocked = false,
  String? lineUiMode,
  TakeoverRequest? takeover,
}) {
  return BootstrapLineState(
    lineId: _lineIdFor[lineNumber]!,
    lineNumber: lineNumber,
    lineName: 'Line $lineNumber',
    isAuthorized: authorized,
    authorizedOperator: (authorized && withOperator)
        ? Operator(id: lineNumber, name: 'Operator $lineNumber')
        : null,
    blockedReason: blockedReason,
    blocked: blocked,
    lineUiMode: lineUiMode,
    pendingTakeoverRequest: takeover,
    takeoverRequestStatus: takeover == null ? null : 'PENDING',
  );
}

BootstrapResponse _bootstrap(List<BootstrapLineState> lines) {
  return BootstrapResponse(productTypes: const [], lines: lines);
}

PalletizerSession _activeSession(int lineId) => PalletizerSession(
  sessionId: lineId,
  palletizerOperatorId: 1,
  palletizerName: 'Palletizer',
  palletizingLineId: lineId,
  palletizingLineName: 'Line',
  status: 'ACTIVE',
);

TakeoverRequest _takeoverRequest({
  TakeoverStatus status = TakeoverStatus.pending,
  String id = 'tk-1',
}) => TakeoverRequest(id: id, status: status);

/// Builds a provider wired to fresh fakes. [tokenLineIds] pre-seeds session
/// tokens so the `/palletizer-session/current` gate is open for those lines.
({PalletizingProvider provider, _FakeRepo repo, _FakeAuthStorage auth})
    _newProvider({List<int> tokenLineIds = const []}) {
  final repo = _FakeRepo();
  final auth = _FakeAuthStorage();
  for (final id in tokenLineIds) {
    auth.seedToken(id);
  }
  final provider = PalletizingProvider(repo, auth, _FakeNotifications());
  return (provider: provider, repo: repo, auth: auth);
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('Palletizer-session endpoint gate', () {
    test('a cold start with no stored token never calls /current', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;

      await t.provider.loadBootstrap();

      // The spam fix: zero session-endpoint calls when no session exists.
      expect(t.repo.sessionCalls, 0);
      expect(t.provider.getUiState(101), LineUiState.needsPalletizerAuth);
      expect(t.provider.getUiState(102), LineUiState.needsPalletizerAuth);
    });

    test('a 404 closes the gate so the endpoint is not retried in a loop',
        () async {
      // A stale token from a prior session — the backend now 404s.
      final t = _newProvider(tokenLineIds: [101]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;

      await t.provider.loadBootstrap();
      // One validating call for the stale token, then PALLETIZER_SESSION_REQUIRED.
      expect(t.repo.sessionCalls, 1);
      expect(t.provider.getUiState(101), LineUiState.needsPalletizerAuth);

      // Subsequent refreshes must not hit the endpoint again.
      await t.provider.refreshPalletizerSession(101);
      await t.provider.pollLineMonitoring();
      expect(t.repo.sessionCalls, 1);
    });

    test('a stored token keeps the gate open and the session loads',
        () async {
      final t = _newProvider(tokenLineIds: [101, 102]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);

      await t.provider.loadBootstrap();

      expect(t.repo.sessionCalls, 2);
      expect(t.provider.getUiState(101), LineUiState.active);
    });

    test('a successful palletizerAuth re-opens the gate', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.loadBootstrap();
      expect(t.repo.sessionCalls, 0); // no token -> gated shut

      t.repo.authFn = (lineId) => PalletizerAuthResult(
            session: _activeSession(lineId),
            sessionToken: 'fresh-token',
          );
      final ok = await t.provider.palletizerAuth(101, '1234');
      expect(ok, isTrue);

      // The gate is open again — a refresh now reaches the endpoint.
      final before = t.repo.sessionCalls;
      await t.provider.refreshPalletizerSession(101);
      expect(t.repo.sessionCalls, before + 1);
    });

    test('logout closes the gate again', () async {
      final t = _newProvider(tokenLineIds: [101]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(101), LineUiState.active);

      await t.provider.palletizerLogout(101);

      final before = t.repo.sessionCalls;
      await t.provider.refreshPalletizerSession(101);
      await t.provider.pollLineMonitoring();
      expect(t.repo.sessionCalls, before);
    });
  });

  group('Adaptive polling cadence', () {
    test('SSE connected + steady uses the slow ~50s safety cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.provider.onSseConnectionStateChanged(SseConnectionState.connected);

      expect(t.provider.hasAnyUrgentLineState, isFalse);
      expect(t.provider.pollCadence, PollCadence.safety);
      expect(t.provider.nextPollInterval, const Duration(seconds: 50));
    });

    test('SSE disconnected + steady uses the ~12s fallback cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      // Default state is disconnected — REST polling is the only channel.
      expect(t.provider.sseConnectionState, SseConnectionState.disconnected);
      expect(t.provider.pollCadence, PollCadence.fallback);
      expect(t.provider.nextPollInterval, const Duration(seconds: 12));
    });

    test('SSE reconnecting also uses the fallback cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.provider.onSseConnectionStateChanged(SseConnectionState.reconnecting);
      expect(t.provider.pollCadence, PollCadence.fallback);
    });

    test('waiting for the Thermoforming operator uses the fast ~6s cadence',
        () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () =>
          _bootstrap([_line(1, authorized: false), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      expect(t.provider.getUiState(101), LineUiState.waitingForThermoforming);
      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
      expect(t.provider.nextPollInterval, const Duration(seconds: 6));
    });

    test('urgent wins even while SSE is connected', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([
            _line(1, takeover: _takeoverRequest()),
            _line(2),
          ]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.provider.onSseConnectionStateChanged(SseConnectionState.connected);

      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
    });

    test('a backend-blocked line uses the fast cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([
            _line(1, blocked: true, blockedReason: 'LINE_IN_HANDOVER'),
            _line(2),
          ]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
    });

    test('an auto-released takeover keeps the fast cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([
            _line(
              1,
              takeover: _takeoverRequest(
                status: TakeoverStatus.postAcceptTimeoutAutoReleased,
              ),
            ),
            _line(2),
          ]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
    });

    test('a pending legacy handover uses the fast cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([
            _line(1, lineUiMode: 'PENDING_HANDOVER_REVIEW'),
            _line(2),
          ]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
    });

    test('hasUrgentLineState is per-line, not global', () async {
      final t = _newProvider(tokenLineIds: [102]);
      t.repo.bootstrapFn = () =>
          _bootstrap([_line(1, authorized: false), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();

      expect(t.provider.hasUrgentLineState(101), isTrue);
      expect(t.provider.hasUrgentLineState(102), isFalse);
      expect(t.provider.hasAnyUrgentLineState, isTrue);
      expect(t.provider.pollCadence, PollCadence.urgent);
    });
  });

  group('Network-failure retry cadence', () {
    test('a fully failed poll round backs off to the ~8s retry cadence',
        () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();
      t.provider.onSseConnectionStateChanged(SseConnectionState.connected);
      expect(t.provider.pollCadence, PollCadence.safety);

      t.repo.lineStateFn = (_) => throw ApiException.network();
      await t.provider.pollLineMonitoring();

      expect(t.provider.lastPollFailed, isTrue);
      expect(t.provider.pollCadence, PollCadence.retry);
      expect(t.provider.nextPollInterval, const Duration(seconds: 8));
    });

    test('a recovered poll round clears the retry back-off', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.repo.lineStateFn = (_) => throw ApiException.network();
      await t.provider.pollLineMonitoring();
      expect(t.provider.pollCadence, PollCadence.retry);

      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.pollLineMonitoring();

      expect(t.provider.lastPollFailed, isFalse);
      // No SSE -> fallback once the retry back-off clears.
      expect(t.provider.pollCadence, PollCadence.fallback);
    });

    test('one line recovering means the round is not counted as failed',
        () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.repo.lineStateFn = (lineId) {
        if (lineId == 101) throw ApiException.network();
        return _line(2);
      };
      await t.provider.pollLineMonitoring();

      expect(t.provider.lastPollFailed, isFalse);
    });

    test('a failed bootstrap arms the retry cadence', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => throw ApiException.network();

      await t.provider.loadBootstrap();

      expect(t.provider.lastPollFailed, isTrue);
      expect(t.provider.pollCadence, PollCadence.retry);
    });
  });

  group('SSE-driven refresh', () {
    PalletizingAppSseEvent frame(String id, {int? line, String? reason}) =>
        PalletizingAppSseEvent(
          eventId: id,
          palletizingLineId: line,
          reason: reason,
        );

    test('an event for a rendered line refreshes just that line', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.refreshFromSseEvents([
        frame('a', line: 101, reason: 'PALLET_CREATED'),
      ]);

      expect(t.repo.lineStateLineIds, [101]); // only the affected line
      expect(t.repo.bootstrapCalls, 1); // no bootstrap re-fetch
    });

    test('events for two rendered lines refresh both lines', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.refreshFromSseEvents([
        frame('a', line: 101, reason: 'PALLET_CREATED'),
        frame('b', line: 102, reason: 'SESSION_CHANGED'),
      ]);

      expect(t.repo.lineStateLineIds.toSet(), {101, 102});
      expect(t.repo.bootstrapCalls, 1);
    });

    test('an event with no line id re-fetches bootstrap instead', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      await t.provider.refreshFromSseEvents([frame('a')]);

      expect(t.repo.bootstrapCalls, 2);
      expect(t.repo.lineStateLineIds, isEmpty);
    });

    test('an SSE refresh never flips the provider into the loading state',
        () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();
      expect(t.provider.state, PalletizingState.loaded);

      final states = <PalletizingState>[];
      t.provider.addListener(() => states.add(t.provider.state));
      await t.provider.refreshFromSseEvents([
        frame('a', line: 101, reason: 'LINE_STATE_CHANGED'),
      ]);

      // Silent bootstrap, not loadBootstrap — no shimmer flash.
      expect(states, isNot(contains(PalletizingState.loading)));
      expect(t.provider.state, PalletizingState.loaded);
    });
  });

  group('Out-of-order /state responses', () {
    test('a stale /state response never overwrites a newer one', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (_) => null;
      await t.provider.loadBootstrap();

      // `/state` for line 101 is served by two completers the test resolves
      // out of order — the newer request first, the older (overtaken) last.
      final cOld = Completer<BootstrapLineState>();
      final cNew = Completer<BootstrapLineState>();
      final handout = <Completer<BootstrapLineState>>[cOld, cNew];
      t.repo.lineStateAsyncFn = (lineId) =>
          lineId == 101 ? handout.removeAt(0).future : Future.value(_line(2));

      // Refresh A starts first and reserves cOld; refresh B reserves cNew.
      final a = t.provider.refreshLineState(101);
      final b = t.provider.refreshLineState(101);

      // The newer refresh (B) lands first with fresh state...
      cNew.complete(_line(1, blocked: true, blockedReason: 'NEWER'));
      // ...then the older refresh (A) lands last with now-stale state.
      cOld.complete(_line(1));
      await Future.wait([a, b]);

      // A's overtaken response was dropped — B's fresh state still stands.
      expect(t.provider.getBlockedReason(101), 'NEWER');
      expect(t.provider.getUiState(101), LineUiState.blocked);
    });
  });

  group('App resume — immediate refresh', () {
    test('re-running loadBootstrap re-fetches and re-routes the UI', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () =>
          _bootstrap([_line(1, authorized: false), _line(2)]);
      t.repo.sessionFn = (_) => null;

      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(101), LineUiState.waitingForThermoforming);
      expect(t.repo.bootstrapCalls, 1);

      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      await t.provider.loadBootstrap();

      expect(t.repo.bootstrapCalls, 2);
      expect(t.provider.getUiState(101), LineUiState.needsPalletizerAuth);
      expect(t.provider.hasUrgentLineState(101), isFalse);
    });
  });

  group('Stale-action handling', () {
    test('a rejected create-pallet immediately refreshes the line state',
        () async {
      final t = _newProvider(tokenLineIds: [101, 102]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(101), LineUiState.active);

      t.repo.createPalletError = ApiException(
        code: 'LINE_BLOCKED_BY_TAKEOVER',
        message: 'blocked',
      );
      t.repo.lineStateFn = (lineId) => _line(
            lineId == 101 ? 1 : 2,
            blocked: true,
            blockedReason: 'LINE_IN_HANDOVER',
          );

      final before = t.repo.lineStateCalls;
      await expectLater(
        t.provider.createPallet(
          lineId: 101,
          productTypeId: 1,
          quantity: 1,
          expectedPlanItemId: 1,
        ),
        throwsA(isA<ApiException>()),
      );

      expect(t.repo.lineStateCalls, greaterThan(before));
      expect(
        t.provider.getLineError(101),
        'لا يمكن إنشاء طبليات الآن — الخط في وضع تسليم. '
        'الرجاء الانتظار حتى يكمل المشغّل استلام الخط.',
      );
      expect(t.provider.getUiState(101), LineUiState.blocked);
      expect(t.provider.hasUrgentLineState(101), isTrue);
    });

    test('a create rejected for a missing palletizer session drops to State B',
        () async {
      final t = _newProvider(tokenLineIds: [101, 102]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(101), LineUiState.active);

      t.repo.createPalletError = ApiException(
        code: 'PALLETIZER_SESSION_REQUIRED',
        message: 'expired',
      );

      await expectLater(
        t.provider.createPallet(
          lineId: 101,
          productTypeId: 1,
          quantity: 1,
          expectedPlanItemId: 1,
        ),
        throwsA(isA<ApiException>()),
      );

      expect(t.provider.getUiState(101), LineUiState.needsPalletizerAuth);
    });
  });

  group('Backend state drives the UI', () {
    test('an active backend state clears the unavailable/waiting UI',
        () async {
      final t = _newProvider(tokenLineIds: [101]);
      t.repo.bootstrapFn = () =>
          _bootstrap([_line(1, authorized: false), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(101), LineUiState.waitingForThermoforming);

      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.refreshLineState(101);

      expect(t.provider.getUiState(101), LineUiState.active);
      expect(t.provider.hasUrgentLineState(101), isFalse);
    });

    test('logout clears transient refresh state', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => throw ApiException.network();
      await t.provider.loadBootstrap();
      expect(t.provider.lastPollFailed, isTrue);

      t.provider.clearTransientRefreshState();

      expect(t.provider.lastPollFailed, isFalse);
    });
  });
}
