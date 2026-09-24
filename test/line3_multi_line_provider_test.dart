// LINE_3 handoff §6.10 — provider tests for an N-line station.
//
// Skewed fixtures (see support/line3_fakes.dart): lineIds 11 / 12 / 13 carry
// lineNumbers 1 / 2 / 3. Nothing may treat a lineNumber or a
// thermoformingLineId as a lineId.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/takeover_request.dart';
import 'package:taleeb_thermoforming/domain/entities/takeover_status.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

import 'support/line3_fakes.dart';

class _Harness {
  final repo = FakePalletizingRepository();
  final auth = FakeAuthStorage();
  final notifications = FakeNotifications();
  DateTime now = DateTime.utc(2026, 9, 16, 8);
  late final PalletizingProvider provider = PalletizingProvider(
    repo,
    auth,
    notifications,
    clock: () => now,
  );

  /// Every lineState served by `/state`, keyed by lineId.
  final Map<int, BootstrapLineState> served = {};

  void serve(List<BootstrapLineState> lines) {
    served
      ..clear()
      ..addEntries(lines.map((l) => MapEntry(l.lineId, l)));
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (lineId) => served[lineId]!;
  }
}

PalletizingAppSseEvent _frame(
  String id, {
  int? line,
  String? reason,
  int? thermoformingLineId,
}) => PalletizingAppSseEvent(
  eventId: id,
  palletizingLineId: line,
  reason: reason,
  thermoformingLineId: thermoformingLineId,
);

void main() {
  group('Enable / disable through a silent bootstrap', () {
    test('LINE_STATE_CHANGED for an unknown line adds it — one silent '
        'bootstrap, no loading state', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.loadBootstrap();
      expect(h.provider.renderedLineIds, [11, 12]);
      expect(h.provider.takeLineNotices(), isEmpty); // first bootstrap: none

      h.serve([
        skewedLine(1),
        skewedLine(2),
        skewedLine(3, waitingForOperator: true),
      ]);
      final states = <PalletizingState>[];
      h.provider.addListener(() => states.add(h.provider.state));

      await h.provider.refreshFromSseEvents([
        _frame('e1', line: 13, reason: 'LINE_STATE_CHANGED'),
      ]);

      expect(h.repo.bootstrapCalls, 2);
      expect(states, isNot(contains(PalletizingState.loading)));
      expect(h.provider.renderedLineIds, [11, 12, 13]);
      expect(h.provider.renderedLines.map((l) => l.label), [
        'خط أ',
        'خط ب',
        'خط ج',
      ]);
      final notices = h.provider.takeLineNotices();
      expect(notices, hasLength(1));
      expect(notices.single.change, LineAvailabilityChange.added);
      expect(notices.single.lineId, 13);
      expect(notices.single.label, 'خط ج');
    });

    test(
      'a disabled line is pruned from every map, polling and cadence',
      () async {
        final h = _Harness();
        h.serve([
          skewedLine(1),
          skewedLine(2),
          skewedLine(3, waitingForOperator: true),
        ]);
        await h.provider.loadBootstrap();
        expect(h.provider.hasUrgentLineState(13), isTrue);
        expect(h.provider.hasAnyUrgentLineState, isTrue);

        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.refreshFromSseEvents([
          _frame('e2', line: 13, reason: 'LINE_STATE_CHANGED'),
        ]);

        expect(h.provider.renderedLineIds, [11, 12]);
        expect(h.provider.isLineRendered(13), isFalse);
        expect(h.provider.getLine(13), isNull);
        expect(h.provider.getPalletizerSessionState(13), isNull);
        expect(h.provider.getTakeover(13), isNull);
        expect(h.provider.hasUrgentLineState(13), isFalse);
        expect(h.provider.hasAnyUrgentLineState, isFalse);

        h.repo.lineStateLineIds.clear();
        await h.provider.pollLineMonitoring();
        expect(h.repo.lineStateLineIds.toSet(), {11, 12});

        // A refresh request for the removed line never reaches the backend.
        h.repo.lineStateLineIds.clear();
        await h.provider.refreshLineState(13);
        expect(h.repo.lineStateLineIds, isEmpty);

        final notices = h.provider.takeLineNotices();
        expect(notices.single.change, LineAvailabilityChange.removed);
        expect(notices.single.label, 'خط ج');
      },
    );

    test(
      'removing the selected line selects the first line and flags it',
      () async {
        final h = _Harness();
        h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
        await h.provider.loadBootstrap();
        h.provider.selectLine(13);

        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.refreshBootstrap();

        expect(h.provider.selectedLineId, 11);
        final notice = h.provider.takeLineNotices().single;
        expect(notice.wasSelected, isTrue);
      },
    );

    test('selection survives 2 → 3 → 2 lines by lineId', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.loadBootstrap();
      h.provider.selectLine(12);

      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.refreshBootstrap();
      expect(h.provider.selectedLineId, 12);

      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.refreshBootstrap();
      expect(h.provider.selectedLineId, 12);
    });

    test(
      'a /state response for a line removed while in flight is dropped',
      () async {
        final h = _Harness();
        h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
        await h.provider.loadBootstrap();

        final pending = Completer<BootstrapLineState>();
        h.repo.lineStateAsyncFn = (id) => id == 13 ? pending.future : null;
        final refresh = h.provider.refreshLineState(13);

        // Line 13 is switched off while its /state call is still in flight.
        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.refreshBootstrap();
        pending.complete(skewedLine(3, waitingForOperator: true));
        await refresh;

        expect(h.provider.isLineRendered(13), isFalse);
        expect(h.provider.getLine(13), isNull);
        expect(h.provider.hasAnyUrgentLineState, isFalse);
      },
    );
  });

  group('SSE routing uses palletizingLineId only', () {
    test('a frame for a rendered line refreshes just that line', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();

      await h.provider.refreshFromSseEvents([
        _frame('e3', line: 13, reason: 'PALLET_CREATED'),
      ]);

      expect(h.repo.lineStateLineIds, [13]);
      expect(h.repo.bootstrapCalls, 1);
    });

    test('a thermoformingLineId never routes a frame: id 4 is unknown, not '
        'line 3', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();

      await h.provider.refreshFromSseEvents([
        // A TF id (4) in the palletizingLineId slot is simply an unknown line.
        _frame('e4', line: 4, reason: 'LINE_TAKEOVER_REQUESTED'),
      ]);

      expect(h.repo.lineStateLineIds, isEmpty); // never routed to lineId 13
      expect(h.repo.bootstrapCalls, 2); // unknown line → bootstrap
    });

    test('a takeover frame carrying thermoformingLineId still routes by '
        'palletizingLineId', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();

      await h.provider.refreshFromSseEvents([
        _frame(
          'e5',
          line: 13,
          reason: 'LINE_TAKEOVER_REQUESTED',
          thermoformingLineId: 4,
        ),
      ]);

      expect(h.repo.lineStateLineIds, [13]);
    });

    test('a frame for a non-rendered (inactive) line re-bootstraps with no '
        'UI change and no alert', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.loadBootstrap();

      await h.provider.refreshFromSseEvents([
        _frame('e6', line: 13, reason: 'MACHINE_ROLL_STATE_UPDATED'),
      ]);

      expect(h.repo.bootstrapCalls, 2);
      expect(h.provider.renderedLineIds, [11, 12]);
      expect(h.provider.takeLineNotices(), isEmpty);
      expect(h.notifications.alertCalls, 0);
    });
  });

  group('Takeover alerts only for rendered lines', () {
    TakeoverRequest pending(String id) =>
        TakeoverRequest(id: id, status: TakeoverStatus.pending);

    test(
      'a takeover on line 13 raises its dialog signal; pruning removes it',
      () async {
        final h = _Harness();
        h.serve([
          skewedLine(1),
          skewedLine(2),
          skewedLine(3, takeover: pending('tk-13')),
        ]);
        await h.provider.loadBootstrap();

        expect(h.notifications.alertCalls, 1);
        expect(h.provider.isTakeoverDialogPending(13), isTrue);

        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.refreshBootstrap();

        expect(h.provider.isTakeoverDialogPending(13), isFalse);
        expect(h.notifications.alertCalls, 1);
      },
    );
  });

  group('Refresh cadence', () {
    test('the safety tick re-bootstraps; earlier ticks poll /state', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.loadBootstrap();
      expect(h.repo.bootstrapCalls, 1);

      h.now = h.now.add(const Duration(seconds: 6));
      await h.provider.onPollTick();
      expect(h.repo.bootstrapCalls, 1);
      expect(h.repo.lineStateLineIds.toSet(), {11, 12});

      h.now = h.now.add(PollCadence.safety.interval);
      await h.provider.onPollTick();
      expect(h.repo.bootstrapCalls, 2);
    });

    test('a failed first load is retried by the next tick', () async {
      final h = _Harness();
      h.repo.bootstrapFn = () => throw ApiException.network();
      await h.provider.loadBootstrap();
      expect(h.provider.state, PalletizingState.error);

      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.onPollTick();

      expect(h.provider.state, PalletizingState.loaded);
      expect(h.provider.renderedLineIds, [11, 12, 13]);
    });

    test('a failed silent refresh keeps the rendered lines', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();

      h.repo.bootstrapFn = () => throw ApiException.network();
      await h.provider.refreshBootstrap();

      expect(h.provider.state, PalletizingState.loaded);
      expect(h.provider.errorMessage, isNull);
      expect(h.provider.renderedLineIds, [11, 12, 13]);
      expect(h.provider.lastPollFailed, isTrue);
    });

    test('a waiting line 13 is urgent exactly like lines 11 / 12', () async {
      final h = _Harness();
      h.serve([
        skewedLine(1),
        skewedLine(2),
        skewedLine(3, waitingForOperator: true),
      ]);
      await h.provider.loadBootstrap();

      expect(h.provider.pollCadence, PollCadence.urgent);
    });

    test(
      'concurrent refreshes coalesce: one in flight plus one trailing',
      () async {
        final h = _Harness();
        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.loadBootstrap();
        final before = h.repo.bootstrapCalls;

        await Future.wait([
          h.provider.refreshBootstrap(),
          h.provider.refreshBootstrap(),
          h.provider.refreshBootstrap(),
        ]);

        expect(h.repo.bootstrapCalls - before, 2);
      },
    );
  });

  group('Line identity surfaces', () {
    test('knownOperatingLineIds == rendered ids', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();
      expect(h.provider.knownOperatingLineIds, [11, 12, 13]);

      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.refreshBootstrap();
      expect(h.provider.knownOperatingLineIds, [11, 12]);
    });

    test('a rename shows up from the latest state', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();

      h.served[13] = skewedLine(3, lineDisplayName: 'خط ج الجديد');
      await h.provider.refreshLineState(13);

      expect(h.provider.getLine(13)!.label, 'خط ج الجديد');
    });

    test('lineNumberForLineId survives pruning (reprint side band)', () async {
      final h = _Harness();
      h.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
      await h.provider.loadBootstrap();
      h.serve([skewedLine(1), skewedLine(2)]);
      await h.provider.refreshBootstrap();

      expect(h.provider.lineNumberForLineId(13), 3);
      expect(h.provider.lineNumberForLineId(99), isNull);
    });

    test(
      'nextUsableLineId walks server order and skips waiting lines',
      () async {
        final h = _Harness();
        h.serve([
          skewedLine(1),
          skewedLine(2, waitingForOperator: true),
          skewedLine(3),
        ]);
        await h.provider.loadBootstrap();

        expect(h.provider.nextUsableLineId(11), 13);
        expect(h.provider.nextUsableLineId(13), 11);
        expect(h.provider.nextUsableLineId(12), 13);
      },
    );
  });

  group('createPallet', () {
    test('forwards expectedPlanItemId for the line', () async {
      final h = _Harness();
      h.serve([
        skewedLine(1, planItemId: 811, planProductId: 30),
        skewedLine(2),
        skewedLine(3, planItemId: 912, planProductId: 31),
      ]);
      await h.provider.loadBootstrap();
      expect(h.provider.getCurrentPlanItemId(13), 912);

      h.repo.createPalletError = ApiException(
        code: 'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED',
        message: 'exceeded',
      );
      await expectLater(
        h.provider.createPallet(
          lineId: 13,
          productTypeId: 31,
          quantity: 40,
          expectedPlanItemId: h.provider.getCurrentPlanItemId(13)!,
        ),
        throwsA(isA<ApiException>()),
      );

      final call = h.repo.createCalls.single;
      expect(call.lineId, 13);
      expect(call.expectedPlanItemId, 912);
    });

    test(
      'PRODUCTION_LINE_INACTIVE re-fetches bootstrap and flags the notice',
      () async {
        final h = _Harness();
        h.serve([
          skewedLine(1),
          skewedLine(2),
          skewedLine(3, planItemId: 912, planProductId: 31),
        ]);
        await h.provider.loadBootstrap();
        h.provider.selectLine(13);

        h.serve([skewedLine(1), skewedLine(2)]);
        h.repo.createPalletError = ApiException(
          code: 'PRODUCTION_LINE_INACTIVE',
          message: 'Production line is inactive',
          statusCode: 400,
        );

        await expectLater(
          h.provider.createPallet(
            lineId: 13,
            productTypeId: 31,
            quantity: 40,
            expectedPlanItemId: 912,
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'PRODUCTION_LINE_INACTIVE',
            ),
          ),
        );

        expect(h.repo.bootstrapCalls, 2);
        expect(h.provider.isLineRendered(13), isFalse);
        final notice = h.provider.takeLineNotices().single;
        expect(notice.change, LineAvailabilityChange.removed);
        expect(notice.wasSelected, isTrue);
        expect(
          ApiException.lineInactiveMessage(notice.label),
          'خط ج غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.',
        );
      },
    );

    test(
      'a line that is no longer rendered is rejected without a request',
      () async {
        final h = _Harness();
        h.serve([skewedLine(1), skewedLine(2)]);
        await h.provider.loadBootstrap();

        await expectLater(
          h.provider.createPallet(
            lineId: 13,
            productTypeId: 31,
            quantity: 40,
            expectedPlanItemId: 912,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(h.repo.createCalls, isEmpty);
      },
    );
  });
}
