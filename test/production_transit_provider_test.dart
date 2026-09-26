// PRODUCTION → TRANSIT («الرصيف») move (V210) — Palletizing App provider.
//
// Contract: docs/FRONTEND_HANDOFF_PALLETIZING_APP_PRODUCTION_TO_TRANSIT_MOVE.md
//   * One Scan, no line picker: the pallet is moved with a palletizer token
//     of this device; the employee whose pending list holds it goes first.
//   * One clientRequestId per physical scan, reused verbatim for every retry
//     (network / timeout / 5xx), discarded after any other answer.
//   * Undone / deleted outcomes are reported truthfully, never as success.
//   * The pending list is token-gated, merged per employee, re-read after
//     every move, PIN login, session end, bootstrap and SSE frame.
//   * Logout and create refusals keep their blockers; a blocked logout keeps
//     the session.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants/production_transit_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/domain/entities/production_transit.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

import 'support/line3_fakes.dart';

const _line = 11; // skewed fixture: lineNumber 1
const _otherLine = 12; // lineNumber 2
const _pallet = '101000000123';
const _otherPallet = '101000000124';

class _Harness {
  final repo = FakePalletizingRepository();
  final auth = FakeAuthStorage();
  int _ids = 0;
  late final PalletizingProvider provider = PalletizingProvider(
    repo,
    auth,
    FakeNotifications(),
    transitRetryDelay: Duration.zero,
    clientRequestIdFactory: () => 'req-${++_ids}',
  );

  /// Renders lines 11 and 12 and logs a palletizer into [sessionLines];
  /// [employeeOf] maps a line to its palletizer's operator id (default 70).
  Future<void> boot({
    Set<int> sessionLines = const {_line},
    Map<int, int> employeeOf = const {},
  }) async {
    final lines = [
      skewedLine(1, planItemId: 912, planProductId: 31),
      skewedLine(2, planItemId: 922, planProductId: 32),
    ];
    final byId = {for (final l in lines) l.lineId: l};
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (id) => byId[id]!;
    for (final id in sessionLines) {
      auth.tokens[id] = 'token-$id';
    }
    repo.sessionFn = (id) => auth.tokens.containsKey(id)
        ? activeSession(id, operatorId: employeeOf[id] ?? 70)
        : null;
    await provider.loadBootstrap();
    await pumpEventQueue();
  }

  Future<TransitMoveOutcome> move(
    String identifier, {
    PalletTransitScanType scanType = PalletTransitScanType.qr,
    int? preferredLineId,
  }) async {
    final outcome = await provider.movePalletToTransit(
      identifier,
      scanType: scanType,
      preferredLineId: preferredLineId,
    );
    await pumpEventQueue();
    return outcome;
  }
}

ApiException _api(
  String code, [
  int status = 409,
  Map<String, dynamic>? details,
]) => ApiException(
  code: code,
  message: 'English developer text',
  statusCode: status,
  details: details,
);

PalletizingAppSseEvent _frame(String id, int line) => PalletizingAppSseEvent(
  eventId: id,
  type: 'LINE_STATE_CHANGED',
  reason: 'PALLET_LOCATION_CHANGED',
  palletizingLineId: line,
);

void main() {
  group('scan (§3.1)', () {
    test('happy scan: line token, raw identifier, QR, fresh id', () async {
      final h = _Harness();
      await h.boot();
      final readsBefore = h.repo.pendingTokens.length;

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.moved);
      expect(outcome.message, ProductionTransitStrings.success);
      expect(outcome.scannedValue, _pallet);
      expect(outcome.result?.movementId, 90211);
      final call = h.repo.moveCalls.single;
      expect(call.sessionToken, 'token-11');
      expect(call.identifier, _pallet);
      expect(call.scanType, PalletTransitScanType.qr);
      expect(call.clientRequestId, 'req-1');
      // The pending list is re-read after the move.
      expect(h.repo.pendingTokens.length, greaterThan(readsBefore));
      expect(h.provider.isTransitMoveInFlight, isFalse);
    });

    test('manual entry with Arabic digits is sent as typed, NUMBER', () async {
      final h = _Harness();
      await h.boot();

      final outcome = await h.move(
        '١٠١٠٠٠٠٠٠١٢٣',
        scanType: PalletTransitScanType.number,
      );

      expect(outcome.status, TransitMoveStatus.moved);
      expect(outcome.scannedValue, _pallet);
      expect(h.repo.moveCalls.single.identifier, '١٠١٠٠٠٠٠٠١٢٣');
      expect(h.repo.moveCalls.single.scanType, PalletTransitScanType.number);
    });

    test('a transient failure is retried once with the same id', () async {
      final h = _Harness();
      await h.boot();
      h.repo.moveResults.addAll([
        ApiException.timeout(),
        transitMoveResult(_pallet),
      ]);

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.moved);
      expect(h.repo.moveCalls.map((c) => c.clientRequestId), [
        'req-1',
        'req-1',
      ]);
      expect(h.repo.moveCalls.map((c) => c.sessionToken).toSet(), {'token-11'});
    });

    test(
      'retry after a lost response reuses the id; the replay is a success',
      () async {
        final h = _Harness();
        await h.boot();
        h.repo.moveResults.addAll([
          ApiException.timeout(),
          ApiException.network(),
        ]);

        final failed = await h.move(_pallet);
        expect(failed.status, TransitMoveStatus.retryable);
        expect(failed.canRetry, isTrue);
        expect(failed.message, ProductionTransitStrings.connectionFailed);

        // The first attempt had committed — the backend replays it.
        h.repo.moveResults.add(transitMoveResult(_pallet, replayed: true));
        final retried = await h.move(_pallet);

        expect(retried.status, TransitMoveStatus.moved);
        expect(retried.result?.replayed, isTrue);
        expect(h.repo.moveCalls.map((c) => c.clientRequestId).toSet(), {
          'req-1',
        });

        // A new scan of the same pallet afterwards is a new id.
        await h.move(_pallet);
        expect(h.repo.moveCalls.last.clientRequestId, 'req-2');
      },
    );

    test('a 5xx is retryable; a different pallet is a new scan', () async {
      final h = _Harness();
      await h.boot();
      h.repo.moveResults.addAll([
        _api('INTERNAL_ERROR', 500),
        _api('INTERNAL_ERROR', 500),
      ]);

      expect((await h.move(_pallet)).status, TransitMoveStatus.retryable);
      await h.move(_otherPallet);

      expect(h.repo.moveCalls.last.clientRequestId, 'req-2');
      expect(h.repo.moveCalls.last.identifier, _otherPallet);
    });

    test('a replay of an undone movement is "returned to the line"', () async {
      final h = _Harness();
      await h.boot();
      h.repo.moveResults.add(
        transitMoveResult(_pallet, replayed: true, movementUndone: true),
      );

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.returnedToProduction);
      expect(outcome.message, ProductionTransitStrings.replayUndone);
      expect(outcome.palletLeftProduction, isFalse);
    });

    for (final (code, status, text) in [
      (
        'PALLET_IDENTIFIER_INVALID',
        400,
        ProductionTransitStrings.identifierInvalid,
      ),
      ('PALLET_NOT_FOUND', 404, ProductionTransitStrings.notFound),
      ('PALLET_CANCELLED', 409, ProductionTransitStrings.cancelled),
      (
        'PALLET_BLOCKED_BY_GRINDING',
        409,
        ProductionTransitStrings.blockedByGrinding,
      ),
      (
        'PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE',
        403,
        ProductionTransitStrings.outsideLineScope,
      ),
      (
        'PALLET_OUTSIDE_CURRENT_OPERATOR_SHIFT',
        403,
        ProductionTransitStrings.outsideOperatorShift,
      ),
      (
        'PALLETIZER_TRANSIT_MOVE_IDEMPOTENCY_KEY_REUSED',
        409,
        ProductionTransitStrings.genericFailure,
      ),
      ('VALIDATION_ERROR', 400, ProductionTransitStrings.genericFailure),
    ]) {
      test('$code: refused once, the next submit is a new scan', () async {
        final h = _Harness();
        await h.boot();
        h.repo.moveResults.add(_api(code, status));

        final outcome = await h.move(_pallet);

        expect(outcome.status, TransitMoveStatus.refused);
        expect(outcome.errorCode, code);
        expect(outcome.message, text);
        expect(h.repo.moveCalls, hasLength(1));

        await h.move(_pallet);
        expect(h.repo.moveCalls.last.clientRequestId, 'req-2');
      });
    }

    test(
      'PALLET_NOT_AT_PRODUCTION is informational with the location',
      () async {
        final h = _Harness();
        h.repo.pendingFn = (_) => pendingList({
          _line: [pendingPallet(_pallet)],
        });
        await h.boot();
        expect(h.provider.productionPendingCount, 1);
        h.repo.moveResults.add(
          _api('PALLET_NOT_AT_PRODUCTION', 409, {
            'palletId': 55011,
            'scannedValue': _pallet,
            'currentLocation': 'TRANSIT',
          }),
        );
        // A driver took it — the backend no longer lists it.
        h.repo.pendingFn = null;

        final outcome = await h.move(_pallet);

        expect(outcome.status, TransitMoveStatus.notAtProduction);
        expect(outcome.message, ProductionTransitStrings.notAtProduction);
        expect(outcome.currentLocation, 'TRANSIT');
        expect(outcome.palletLeftProduction, isTrue);
        expect(h.provider.productionPendingCount, 0);
      },
    );

    test('VOIDED at PRODUCTION needs a new scan with a new id', () async {
      final h = _Harness();
      await h.boot();
      h.repo.moveResults.add(
        _api('PALLETIZER_TRANSIT_MOVE_REQUEST_VOIDED', 409, {
          'palletId': 55012,
          'scannedValue': _pallet,
          'currentLocation': 'PRODUCTION',
        }),
      );

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.voided);
      expect(outcome.message, ProductionTransitStrings.requestVoided);
      expect(outcome.needsNewScan, isTrue);
      expect(outcome.palletLeftProduction, isFalse);

      await h.move(_pallet);
      expect(h.repo.moveCalls.last.clientRequestId, 'req-2');
    });

    test('PALLETIZER_SESSION_REQUIRED goes to PIN login, no retry', () async {
      final h = _Harness();
      await h.boot();
      h.repo.moveResults.add(_api('PALLETIZER_SESSION_REQUIRED', 401));

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.sessionLost);
      expect(h.repo.moveCalls, hasLength(1));
      expect(h.provider.getUiState(_line), LineUiState.needsPalletizerAuth);
      expect(h.auth.tokens.containsKey(_line), isFalse);
      expect(h.provider.canMoveToTransit, isFalse);
    });

    test('a second submit while one is in flight sends nothing', () async {
      final h = _Harness();
      await h.boot();
      final gate = Completer<void>();
      h.repo.moveGate = gate;

      final first = h.provider.movePalletToTransit(_pallet);
      expect(h.provider.isTransitMoveInFlight, isTrue);
      final second = await h.provider.movePalletToTransit(_pallet);
      gate.complete();

      expect(second.status, TransitMoveStatus.ignored);
      expect((await first).status, TransitMoveStatus.moved);
      expect(h.repo.moveCalls, hasLength(1));
    });

    test('without a palletizer session nothing is sent', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {});

      expect(h.provider.canMoveToTransit, isFalse);
      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.ignored);
      expect(h.repo.moveCalls, isEmpty);
    });
  });

  group('several lines on one device (§8)', () {
    test('same employee on two lines: one read covers both', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet)],
        _otherLine: [pendingPallet(_otherPallet, palletId: 55099)],
      });
      await h.boot(sessionLines: const {_line, _otherLine});
      h.repo.pendingTokens.clear();

      await h.provider.refreshProductionPending();

      expect(h.repo.pendingTokens, hasLength(1));
      expect(h.provider.productionPendingCount, 2);
      expect(
        h.provider.productionPendingLines.map((l) => l.palletizingLineId),
        [_line, _otherLine],
      );
    });

    test('two employees: one read each, merged by line', () async {
      final h = _Harness();
      h.repo.pendingFn = (token) => token == 'token-11'
          ? pendingList({
              _line: [pendingPallet(_pallet)],
            })
          : pendingList({
              _otherLine: [pendingPallet(_otherPallet, palletId: 55099)],
            });
      await h.boot(
        sessionLines: const {_line, _otherLine},
        employeeOf: const {_line: 70, _otherLine: 71},
      );
      h.repo.pendingTokens.clear();

      await h.provider.refreshProductionPending();

      expect(h.repo.pendingTokens.toSet(), {'token-11', 'token-12'});
      expect(h.provider.productionPendingCount, 2);
    });

    test('a listed pallet is moved with its own employee\'s token', () async {
      final h = _Harness();
      h.repo.pendingFn = (token) => token == 'token-12'
          ? pendingList({
              _otherLine: [pendingPallet(_otherPallet)],
            })
          : pendingList({_line: []});
      await h.boot(
        sessionLines: const {_line, _otherLine},
        employeeOf: const {_line: 70, _otherLine: 71},
      );

      await h.move(_otherPallet);

      expect(h.repo.moveCalls.single.sessionToken, 'token-12');
    });

    test(
      'an unlisted pallet falls through to the next employee, same id',
      () async {
        final h = _Harness();
        await h.boot(
          sessionLines: const {_line, _otherLine},
          employeeOf: const {_line: 70, _otherLine: 71},
        );
        h.repo.moveResults.addAll([
          _api('PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE', 403),
          transitMoveResult(_pallet, lineId: _otherLine),
        ]);

        final outcome = await h.move(_pallet);

        expect(outcome.status, TransitMoveStatus.moved);
        expect(h.repo.moveCalls.map((c) => c.sessionToken), [
          'token-11',
          'token-12',
        ]);
        expect(h.repo.moveCalls.map((c) => c.clientRequestId).toSet(), {
          'req-1',
        });
      },
    );

    test('one employee on two lines is tried once, not per line', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {_line, _otherLine});
      h.repo.moveResults.add(_api('PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE', 403));

      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.refused);
      expect(h.repo.moveCalls, hasLength(1));
    });
  });

  group('pending list (§3.2 / §6)', () {
    test('never read without a palletizer session', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {});
      await h.provider.refreshProductionPending();

      expect(h.repo.pendingTokens, isEmpty);
      expect(h.provider.productionPendingLines, isEmpty);
    });

    test('read on bootstrap with the session token', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet, inherited: true)],
      });
      await h.boot();

      expect(h.repo.pendingTokens, contains('token-11'));
      expect(h.provider.hasLoadedProductionPending, isTrue);
      final pallet = h.provider.productionPendingLines.single.pallets.single;
      expect(pallet.inherited, isTrue);
    });

    test('every SSE frame re-reads the list (driver move)', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet)],
      });
      await h.boot();
      expect(h.provider.productionPendingCount, 1);

      // A driver moved it on the Warehouse App.
      h.repo.pendingFn = (_) => pendingList({_line: []});
      await h.provider.refreshFromSseEvents([_frame('e-1', _line)]);
      await pumpEventQueue();

      expect(h.provider.productionPendingCount, 0);
    });

    test('logout of the last session clears the list', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet)],
      });
      await h.boot();

      await h.provider.palletizerLogout(_line);
      await pumpEventQueue();

      expect(h.provider.productionPendingLines, isEmpty);
      expect(h.provider.canMoveToTransit, isFalse);
    });

    test('a read that loses its session drops that line', () async {
      final h = _Harness();
      await h.boot();
      h.repo.pendingFn = (_) => throw _api('PALLETIZER_SESSION_REQUIRED', 401);

      await h.provider.refreshProductionPending();
      await pumpEventQueue();

      expect(h.provider.getUiState(_line), LineUiState.needsPalletizerAuth);
    });

    test('the list is never edited locally — only a read changes it', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet)],
      });
      await h.boot();

      // The move succeeds but the backend still lists the pallet.
      final outcome = await h.move(_pallet);

      expect(outcome.status, TransitMoveStatus.moved);
      expect(h.provider.productionPendingCount, 1);
      expect(
        h.provider.productionPendingLine(_line)!.pallets.single.scannedValue,
        _pallet,
      );
      expect(h.provider.isProductionPendingConfirmed, isTrue);
    });

    test('a failed read is never a confirmation', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({_line: []});
      await h.boot();
      expect(h.provider.isProductionPendingConfirmed, isTrue);

      h.repo.pendingFn = (_) => throw ApiException.network();
      await h.provider.refreshProductionPending();

      expect(h.provider.isProductionPendingConfirmed, isFalse);
      expect(h.provider.productionPendingReadFailed, isTrue);
    });

    test(
      'a changed pending set re-reads an open shift production detail',
      () async {
        final h = _Harness();
        h.repo.pendingFn = (_) => pendingList({
          _line: [pendingPallet(_pallet)],
        });
        await h.boot();
        final before = h.provider.sessionDataRevision(_line);

        // Same pallets — no re-read.
        await h.provider.refreshProductionPending();
        expect(h.provider.sessionDataRevision(_line), before);

        // A driver moved it.
        h.repo.pendingFn = (_) => pendingList({_line: []});
        await h.provider.refreshProductionPending();
        expect(h.provider.sessionDataRevision(_line), before + 1);
      },
    );

    test('a failed read keeps the last known list', () async {
      final h = _Harness();
      h.repo.pendingFn = (_) => pendingList({
        _line: [pendingPallet(_pallet)],
      });
      await h.boot();
      h.repo.pendingFn = (_) => throw ApiException.network();

      await h.provider.refreshProductionPending();

      expect(h.provider.productionPendingCount, 1);
    });
  });

  group('guards (§3.4)', () {
    test('a blocked logout keeps the session and lists the pallets', () async {
      final h = _Harness();
      await h.boot();
      h.repo.logoutErrors[_line] = _api(
        'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS',
        409,
        {
          'pendingProductionPalletCount': 1,
          'blockedLines': [
            {
              'thermoformingShiftLineId': 3120,
              'palletizingLineId': _line,
              'palletizingLineName': 'خط أ',
              'count': 1,
              'pallets': [
                {
                  'palletId': 55011,
                  'scannedValue': _pallet,
                  'currentLocation': 'PRODUCTION',
                  'producedAt': '2026-09-24T11:40:00Z',
                  'inherited': false,
                },
              ],
            },
          ],
        },
      );

      ApiException? thrown;
      try {
        await h.provider.palletizerLogout(_line);
      } on ApiException catch (e) {
        thrown = e;
      }

      expect(thrown?.code, 'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS');
      expect(h.provider.hasActivePalletizerSession(_line), isTrue);
      expect(h.auth.tokens[_line], 'token-11');
      final blockers = h.provider.productionBlockersOf(thrown!)!;
      expect(blockers.pallets.single.scannedValue, _pallet);
    });

    test('other logout failures still end the session locally', () async {
      final h = _Harness();
      await h.boot();
      h.repo.logoutErrors[_line] = ApiException.network();

      await h.provider.palletizerLogout(_line);

      expect(h.provider.hasActivePalletizerSession(_line), isFalse);
    });

    test('a blocked create is rethrown with the line\'s blockers', () async {
      final h = _Harness();
      await h.boot();
      h.repo.createPalletError = _api(
        'PREVIOUS_PALLET_STILL_AT_PRODUCTION',
        409,
        {
          'thermoformingShiftLineId': 3120,
          'productTypeId': 31,
          'blockingPalletCount': 1,
          'blockingPallets': [
            {
              'palletId': 55011,
              'scannedValue': _pallet,
              'productTypeId': 31,
              'currentLocation': 'PRODUCTION',
              'inherited': false,
            },
          ],
        },
      );
      final readsBefore = h.repo.pendingTokens.length;

      ApiException? thrown;
      try {
        await h.provider.createPallet(
          lineId: _line,
          productTypeId: 31,
          quantity: 100,
          expectedPlanItemId: 912,
        );
      } on ApiException catch (e) {
        thrown = e;
      }
      await pumpEventQueue();

      expect(thrown?.code, 'PREVIOUS_PALLET_STILL_AT_PRODUCTION');
      final blockers = h.provider.productionBlockersOf(thrown!, lineId: _line)!;
      expect(blockers.lines.single.palletizingLineId, _line);
      expect(blockers.lines.single.palletizingLineName, 'خط أ');
      expect(blockers.pallets.single.scannedValue, _pallet);
      expect(h.repo.pendingTokens.length, greaterThan(readsBefore));
    });
  });
}
