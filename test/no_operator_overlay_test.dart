// Regression tests for the "no Thermoforming Operator" blocking overlay.
//
// Bug: a line with no operator is reported by the backend as
// `authorized: false` / `authorization: null` AND commonly also carries a
// non-empty `blockedReason` (e.g. LINE_NOT_AUTHORIZED). The old `getUiState`
// checked `blockedReason` first, so the line routed to `LineUiState.blocked`
// — a state ProductionLineSection renders NO overlay for — leaving the bare
// grey "المشغّل: غير متوفر" cards on screen with no blocking modal.
//
// These tests pin the precedence: whenever the same backend data that makes
// LineContextStrip render "غير متوفر" is present, `getUiState` must return
// `waitingForThermoforming` (the state ProductionLineSection covers with the
// blocking ThermoformingWaitingCard) — even when a `blockedReason` is also
// set. They run entirely at the provider level: no widgets, deterministic.

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
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
import 'package:taleeb_thermoforming/domain/entities/print_attempt_result.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/repositories/palletizing_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

// ─────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────

class _FakeRepo implements PalletizingRepository {
  BootstrapResponse Function()? bootstrapFn;
  BootstrapLineState Function(int lineId)? lineStateFn;
  PalletizerSession? Function(int lineId)? sessionFn;

  @override
  Future<BootstrapResponse> bootstrap() async {
    final fn = bootstrapFn;
    if (fn == null) throw StateError('bootstrapFn not configured');
    return fn();
  }

  @override
  Future<BootstrapLineState> getLineState(int lineId) async {
    final fn = lineStateFn;
    if (fn == null) throw StateError('lineStateFn not configured');
    return fn(lineId);
  }

  @override
  Future<PalletizerSession> getCurrentPalletizerSession(int lineId) async {
    final session = sessionFn?.call(lineId);
    if (session == null) {
      throw ApiException(
        code: 'PALLETIZER_SESSION_REQUIRED',
        message: 'no session',
      );
    }
    return session;
  }

  // ── Endpoints not exercised by these tests ──
  @override
  Future<PalletizerAuthResult> palletizerAuth({
    required int lineId,
    required String pin,
  }) => throw UnimplementedError();

  @override
  Future<PalletCreateResponse> createLinePallet({
    required int lineId,
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
  }) => throw UnimplementedError();

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
}

class _FakeAuthStorage extends AuthLocalStorage {
  final Map<int, String> _tokens = {};

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

class _FakeNotifications extends TakeoverNotificationService {
  @override
  Future<void> alert() async {}

  @override
  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────
// Builders
// ─────────────────────────────────────────────────────────────────────────

const _lineIdFor = {1: 101, 2: 102};

final _productionLines = [
  const ProductionLine(id: 101, name: 'L1', code: 'L1', lineNumber: 1),
  const ProductionLine(id: 102, name: 'L2', code: 'L2', lineNumber: 2),
];

/// Builds a line state. [withOperator] controls whether an `authorization`
/// object exists — i.e. exactly what makes LineContextStrip show the operator
/// name vs. "غير متوفر". The `waitingForOperator*` params drive the V81+
/// (2026-05-21) backend-authoritative signal for the waiting overlay.
BootstrapLineState _line(
  int lineNumber, {
  bool authorized = true,
  bool withOperator = true,
  String? blockedReason,
  bool blocked = false,
  String? lineUiMode,
  bool waitingForOperator = false,
  String? waitingForOperatorReason,
  String? waitingForOperatorMessageTitle,
  String? waitingForOperatorMessage,
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
    waitingForOperator: waitingForOperator,
    waitingForOperatorReason: waitingForOperatorReason,
    waitingForOperatorMessageTitle: waitingForOperatorMessageTitle,
    waitingForOperatorMessage: waitingForOperatorMessage,
  );
}

BootstrapResponse _bootstrap(List<BootstrapLineState> lines) => BootstrapResponse(
  productTypes: const [],
  productionLines: _productionLines,
  lines: lines,
);

PalletizerSession _activeSession(int lineId) => PalletizerSession(
  sessionId: lineId,
  palletizerOperatorId: 1,
  palletizerName: 'Palletizer',
  palletizingLineId: lineId,
  palletizingLineName: 'Line',
  status: 'ACTIVE',
);

({PalletizingProvider provider, _FakeRepo repo, _FakeAuthStorage auth})
_newProvider({List<int> tokenLineIds = const []}) {
  final repo = _FakeRepo();
  final auth = _FakeAuthStorage();
  for (final id in tokenLineIds) {
    auth.seedToken(id);
  }
  return (
    provider: PalletizingProvider(repo, auth, _FakeNotifications()),
    repo: repo,
    auth: auth,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('No-operator blocking overlay — getUiState precedence', () {
    test(
      'REGRESSION: a no-operator line that ALSO carries a blockedReason '
      'routes to waitingForThermoforming (not blocked) so the overlay shows',
      () async {
        final t = _newProvider();
        // The exact production payload from the screenshot: no active
        // operator AND the backend stamped a blockedReason.
        t.repo.bootstrapFn = () => _bootstrap([
          _line(
            1,
            authorized: false,
            withOperator: false,
            blockedReason: 'LINE_NOT_AUTHORIZED',
          ),
          _line(2),
        ]);
        t.repo.sessionFn = (_) => null;

        await t.provider.loadBootstrap();

        // Before the fix this was LineUiState.blocked → no overlay.
        expect(
          t.provider.getUiState(1),
          LineUiState.waitingForThermoforming,
          reason: 'no operator must win over blockedReason',
        );
        // Pallet creation stays blocked while there is no operator.
        expect(t.provider.isPalletCreationBlocked(1), isTrue);
      },
    );

    test('a no-operator line with no blockedReason also waits', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => _bootstrap([
        _line(1, authorized: false, withOperator: false),
        _line(2),
      ]);
      t.repo.sessionFn = (_) => null;

      await t.provider.loadBootstrap();

      expect(t.provider.getUiState(1), LineUiState.waitingForThermoforming);
    });

    test(
      'authorized:true but a missing authorization object still waits '
      '(stale authorization row / ended shift)',
      () async {
        final t = _newProvider();
        t.repo.bootstrapFn = () => _bootstrap([
          _line(1, authorized: true, withOperator: false),
          _line(2),
        ]);
        t.repo.sessionFn = (_) => null;

        await t.provider.loadBootstrap();

        expect(t.provider.getUiState(1), LineUiState.waitingForThermoforming);
      },
    );

    test(
      'a real backend block on a line that HAS an operator still routes to '
      'blocked — a genuine block is never relabelled as "no operator"',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([
          _line(1, blockedReason: 'EQUIPMENT_FAULT', blocked: true),
          _line(2),
        ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.getUiState(1), LineUiState.blocked);
      },
    );

    test(
      'pending handover still wins over the no-operator check',
      () async {
        final t = _newProvider();
        t.repo.bootstrapFn = () => _bootstrap([
          _line(
            1,
            authorized: false,
            withOperator: false,
            lineUiMode: 'PENDING_HANDOVER_NEEDS_INCOMING',
          ),
          _line(2),
        ]);
        t.repo.sessionFn = (_) => null;

        await t.provider.loadBootstrap();

        expect(
          t.provider.getUiState(1),
          LineUiState.pendingHandoverIncoming,
        );
      },
    );

    test('an authorized line with an operator and a session is active — '
        'no overlay', () async {
      final t = _newProvider(tokenLineIds: [101]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);

      await t.provider.loadBootstrap();

      expect(t.provider.getUiState(1), LineUiState.active);
    });
  });

  group('No-operator overlay — loading & failed-refresh do not trigger it', () {
    test('a freshly-built provider is idle — the screen shows the shimmer, '
        'not the overlay', () {
      final t = _newProvider();
      // _buildBody renders the shimmer (not ProductionLineSection, and so not
      // the overlay) while state is idle/loading.
      expect(t.provider.state, PalletizingState.idle);
    });

    test('a failed bootstrap surfaces an error — not the "no operator" '
        'overlay', () async {
      final t = _newProvider();
      t.repo.bootstrapFn = () => throw ApiException.network();

      await t.provider.loadBootstrap();

      // _buildBody renders the error screen, gated before ProductionLineSection.
      expect(t.provider.state, PalletizingState.error);
      expect(t.provider.errorMessage, isNotNull);
    });

    test('a temporary failed refresh does NOT flip an active line into the '
        'waiting state', () async {
      final t = _newProvider(tokenLineIds: [101, 102]);
      t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(1), LineUiState.active);

      // The next poll round fails outright (network down).
      t.repo.lineStateFn = (_) => throw ApiException.network();
      await t.provider.pollLineMonitoring();

      // The last good state is preserved — the overlay must not appear.
      expect(t.provider.getUiState(1), LineUiState.active);
    });
  });

  group('No-operator overlay — auto-dismiss on backend recovery', () {
    test('once the backend reports a real operator the line leaves the '
        'waiting state and the overlay closes', () async {
      final t = _newProvider(tokenLineIds: [101]);
      t.repo.bootstrapFn = () => _bootstrap([
        _line(
          1,
          authorized: false,
          withOperator: false,
          blockedReason: 'LINE_NOT_AUTHORIZED',
        ),
        _line(2),
      ]);
      t.repo.sessionFn = (lineId) => _activeSession(lineId);
      await t.provider.loadBootstrap();
      expect(t.provider.getUiState(1), LineUiState.waitingForThermoforming);

      // The Thermoforming Operator claims the line; a refresh picks it up.
      t.repo.lineStateFn = (lineId) => _line(lineId == 101 ? 1 : 2);
      await t.provider.refreshLineState(1);

      expect(t.provider.getUiState(1), LineUiState.active);
      expect(t.provider.isPalletCreationBlocked(1), isFalse);
    });
  });

  // V81+ (2026-05-21): the backend now ships an explicit `waitingForOperator`
  // flag plus localized Arabic copy on `LineStateResponse` for
  // thermoforming-linked lines without an active operator. The provider must
  // (a) treat the flag as authoritative for `getUiState`, in addition to the
  // existing derived clauses kept as defense-in-depth, and (b) surface the
  // backend strings through `getWaitingForOperatorTitle` / `…Message`, with
  // `null` for absent / whitespace values so the card falls back to its
  // hardcoded Arabic copy.
  group('Waiting-for-Operator backend signal (V81+, 2026-05-21)', () {
    test(
      'getUiState returns waitingForThermoforming when waitingForOperator=true '
      'even if isAuthorized=true and authorizedOperator != null '
      '(defense-in-depth — backend flag is the canonical signal)',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        // The "impossible" combination per the backend matrix: present
        // operator AND waiting flag. The provider must still route to the
        // overlay because the backend flag wins.
        t.repo.bootstrapFn = () => _bootstrap([
          _line(
            1,
            authorized: true,
            withOperator: true,
            waitingForOperator: true,
            waitingForOperatorReason: 'NO_ACTIVE_THERMOFORMING_OPERATOR',
            waitingForOperatorMessageTitle: 'بانتظار استلام الخط',
            waitingForOperatorMessage: 'تم إنهاء مناوبة مشغّل التشكيل…',
          ),
          _line(2),
        ]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.isWaitingForOperator(1), isTrue);
        expect(
          t.provider.getUiState(1),
          LineUiState.waitingForThermoforming,
          reason: 'backend waitingForOperator flag must drive the overlay',
        );
        expect(t.provider.isPalletCreationBlocked(1), isTrue);
      },
    );

    test(
      'getWaitingForOperatorTitle / …Message return backend strings verbatim '
      'when populated',
      () async {
        final t = _newProvider();
        t.repo.bootstrapFn = () => _bootstrap([
          _line(
            1,
            authorized: false,
            withOperator: false,
            waitingForOperator: true,
            waitingForOperatorMessageTitle: 'بانتظار استلام الخط',
            waitingForOperatorMessage:
                'تم إنهاء مناوبة مشغّل التشكيل أو لا يوجد مشغّل حالي على هذا الخط.',
          ),
          _line(2),
        ]);
        t.repo.sessionFn = (_) => null;

        await t.provider.loadBootstrap();

        expect(
          t.provider.getWaitingForOperatorTitle(1),
          'بانتظار استلام الخط',
        );
        expect(
          t.provider.getWaitingForOperatorMessage(1),
          startsWith('تم إنهاء مناوبة'),
        );
      },
    );

    test(
      'getWaitingForOperatorTitle / …Message return null when the strings are '
      'absent or whitespace-only (card falls back to hardcoded Arabic)',
      () async {
        final t = _newProvider();
        t.repo.bootstrapFn = () => _bootstrap([
          // No strings set — pre-V81+ shape or non-thermoforming line.
          _line(1, authorized: false, withOperator: false),
          // Whitespace-only — defensive; provider trims and returns null.
          _line(
            2,
            authorized: false,
            withOperator: false,
            waitingForOperator: true,
            waitingForOperatorMessageTitle: '   ',
            waitingForOperatorMessage: '\n\t',
          ),
        ]);
        t.repo.sessionFn = (_) => null;

        await t.provider.loadBootstrap();

        expect(t.provider.getWaitingForOperatorTitle(1), isNull);
        expect(t.provider.getWaitingForOperatorMessage(1), isNull);
        expect(t.provider.getWaitingForOperatorTitle(2), isNull);
        expect(t.provider.getWaitingForOperatorMessage(2), isNull);
        // The existing derived clauses still route both lines to the overlay.
        expect(t.provider.getUiState(1), LineUiState.waitingForThermoforming);
        expect(t.provider.getUiState(2), LineUiState.waitingForThermoforming);
      },
    );

    test(
      'isWaitingForOperator defaults to false on legacy lines without the '
      'new backend fields',
      () async {
        final t = _newProvider(tokenLineIds: [101]);
        t.repo.bootstrapFn = () => _bootstrap([_line(1), _line(2)]);
        t.repo.sessionFn = (lineId) => _activeSession(lineId);

        await t.provider.loadBootstrap();

        expect(t.provider.isWaitingForOperator(1), isFalse);
      },
    );
  });
}
