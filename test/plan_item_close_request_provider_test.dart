// Plan-item close handshake (V190) — Palletizing App provider tests.
//
// Contract: docs/frontend-handoffs/PALLETIZING_PLAN_ITEM_CLOSE_CONFIRMATION.md
// in the backend repository.
//   * The pending read is token-gated, never called before PIN login, and is
//     the ONLY source of the request state (SSE frames are nudges).
//   * It is re-read after login, on bootstrap (start / resume / reconnect),
//     on every PLAN_ITEM_CLOSE_* frame, on line selection, after every
//     decision, and on a throttled poll.
//   * Decisions send the session token, never double-submit, retry a
//     transient failure once, and map every §17 outcome.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants/plan_item_close_request_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/data/models/plan_item_close_request_model.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/entities/plan_item_close_request.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

import 'support/line3_fakes.dart';

const _line = 11; // skewed fixture: lineNumber 1
const _otherLine = 12; // lineNumber 2
const _requestId = 3021;

class _Harness {
  final repo = FakePalletizingRepository();
  final auth = FakeAuthStorage();
  DateTime now = DateTime.utc(2026, 9, 16, 8);
  late final PalletizingProvider provider = PalletizingProvider(
    repo,
    auth,
    FakeNotifications(),
    clock: () => now,
    closeDecisionRetryDelay: Duration.zero,
  );

  /// Renders lines 11 and 12 (both authorized, both with a plan item) and
  /// gives [sessionLines] a stored token plus an ACTIVE session. [request]
  /// is what the backend's pending read serves for its own line.
  Future<void> boot({
    Set<int> sessionLines = const {_line},
    PlanItemCloseRequest? request,
  }) async {
    serve([
      skewedLine(1, planItemId: 912, planProductId: 31),
      skewedLine(2, planItemId: 922, planProductId: 32),
    ]);
    for (final id in sessionLines) {
      auth.tokens[id] = 'token-$id';
    }
    repo.sessionFn = (id) =>
        auth.tokens.containsKey(id) ? activeSession(id) : null;
    if (request != null) {
      repo.activeCloseRequests[request.palletizingLineId] = request;
    }
    await provider.loadBootstrap();
  }

  void serve(List<BootstrapLineState> lines) {
    final byId = {for (final l in lines) l.lineId: l};
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (id) => byId[id]!;
  }

  List<CloseRequestCall> readsFor(int lineId) =>
      repo.closeRequestReads.where((c) => c.lineId == lineId).toList();
}

PlanItemCloseRequest _waiting({int lineId = _line, int id = _requestId}) =>
    closeRequest(id: id, lineId: lineId);

PalletizingAppSseEvent _frame(String id, int line, String reason) =>
    PalletizingAppSseEvent(
      eventId: id,
      type: 'LINE_STATE_CHANGED',
      reason: reason,
      palletizingLineId: line,
      // A different id space — never used for routing.
      thermoformingLineId: 4,
    );

ApiException _api(String code, [int status = 409]) => ApiException(
  code: code,
  message: 'English developer text',
  statusCode: status,
);

void main() {
  group('wire model (handoff §3 / §9)', () {
    test('parses an active request verbatim from §3.1', () {
      final parsed = PlanItemCloseRequestModel.activeFromJson({
        'hasActiveRequest': true,
        'request': {
          'closeRequestId': 3021,
          'status': 'WAITING_FOR_PALLETIZER_DECISION',
          'productionPlanItemId': 812,
          'productTypeId': 31,
          'productTypeName': 'علبة 500 مل شفاف',
          'targetPackageQuantity': 2000,
          'producedPackageQuantity': 1840,
          'thermoformingLineId': 4,
          'palletizingLineId': 9,
          'requestedByOperatorName': 'محمد أحمد',
          'requestedAt': '2026-09-14T08:15:02.418Z',
        },
      })!;
      expect(parsed.closeRequestId, 3021);
      expect(parsed.isWaitingForDecision, isTrue);
      expect(parsed.status.isActive, isTrue);
      expect(parsed.productionPlanItemId, 812);
      expect(parsed.productTypeName, 'علبة 500 مل شفاف');
      expect(parsed.producedPackageQuantity, 1840);
      expect(parsed.targetPackageQuantity, 2000);
      expect(parsed.thermoformingLineId, 4);
      expect(parsed.palletizingLineId, 9);
      expect(parsed.requestedByOperatorName, 'محمد أحمد');
      expect(parsed.requestedAt, DateTime.utc(2026, 9, 14, 8, 15, 2, 418));
      expect(parsed.alreadyProcessed, isFalse);
    });

    test('hasActiveRequest:false means no request', () {
      expect(
        PlanItemCloseRequestModel.activeFromJson({'hasActiveRequest': false}),
        isNull,
      );
    });

    test('parses the P3 response with alreadyProcessed', () {
      final parsed = PlanItemCloseRequestModel.fromJson({
        'closeRequestId': 3021,
        'status': 'CONFIRMED',
        'productionPlanItemId': 812,
        'productTypeId': 31,
        'targetPackageQuantity': 2000,
        'producedPackageQuantity': 2000,
        'thermoformingLineId': 4,
        'palletizingLineId': 9,
        'requestedByOperatorName': 'محمد أحمد',
        'requestedAt': '2026-09-14T08:15:02.418Z',
        'confirmedAt': '2026-09-14T08:31:11.950Z',
        'confirmedByPalletizerName': 'أحمد خالد',
        'resultingNextItemId': 813,
        'alreadyProcessed': true,
      });
      expect(parsed.status, PlanItemCloseRequestStatus.confirmed);
      expect(parsed.status.isActive, isFalse);
      expect(parsed.resultingNextItemId, 813);
      expect(parsed.alreadyProcessed, isTrue);
    });

    test('every status maps; an unknown one is inactive', () {
      expect(
        PlanItemCloseRequestStatus.fromString('PALLETIZER_COMPLETING_PALLETS'),
        PlanItemCloseRequestStatus.palletizerCompletingPallets,
      );
      expect(
        PlanItemCloseRequestStatus.fromString('CANCELLED'),
        PlanItemCloseRequestStatus.cancelled,
      );
      expect(
        PlanItemCloseRequestStatus.fromString('INVALIDATED'),
        PlanItemCloseRequestStatus.invalidated,
      );
      final unknown = PlanItemCloseRequestStatus.fromString('SOMETHING_NEW');
      expect(unknown, PlanItemCloseRequestStatus.unknown);
      expect(unknown.isActive, isFalse);
    });

    test('a request without an id is rejected, never shown', () {
      expect(
        () => PlanItemCloseRequestModel.fromJson({
          'status': 'WAITING_FOR_PALLETIZER_DECISION',
          'productionPlanItemId': 812,
          'palletizingLineId': 9,
        }),
        throwsFormatException,
      );
    });
  });

  group('pending read — when it runs', () {
    test('before PIN login nothing is read and nothing is shown', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {}, request: _waiting());

      expect(h.repo.closeRequestReads, isEmpty);
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
    });

    test('app restart: a stored session restores the WAITING request on the '
        'first bootstrap, read with that line\'s own token', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      final reads = h.readsFor(_line);
      expect(reads, hasLength(1));
      expect(reads.single.sessionToken, 'token-$_line');
      expect(h.readsFor(_otherLine), isEmpty, reason: 'no session on 12');
      expect(h.provider.getActiveCloseRequest(_line)?.closeRequestId, 3021);
      expect(h.provider.firstLineAwaitingCloseDecision(), _line);
    });

    test('PIN login reads a request that was sent while nobody was logged '
        'in (Appendix D)', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {});
      h.repo.activeCloseRequests[_line] = _waiting();
      h.repo.authFn = (id) => PalletizerAuthResult(
        session: activeSession(id),
        sessionToken: 'fresh-token',
      );

      expect(await h.provider.palletizerAuth(_line, '1234'), isTrue);

      expect(h.readsFor(_line).single.sessionToken, 'fresh-token');
      expect(h.provider.firstLineAwaitingCloseDecision(), _line);
    });

    test('a PLAN_ITEM_CLOSE_REQUESTED frame re-reads that line exactly once; '
        'a line without a session is never read', () async {
      final h = _Harness();
      await h.boot();
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      h.repo.closeRequestReads.clear();

      h.repo.activeCloseRequests[_line] = _waiting();
      await h.provider.refreshFromSseEvents([
        _frame('e1', _line, 'PLAN_ITEM_CLOSE_REQUESTED'),
        _frame('e2', _line, 'PLAN_ITEM_CLOSE_REQUESTED'),
        _frame('e3', _otherLine, 'PLAN_ITEM_CLOSE_REQUESTED'),
      ]);

      expect(h.readsFor(_line), hasLength(1));
      expect(h.readsFor(_otherLine), isEmpty);
      expect(h.provider.firstLineAwaitingCloseDecision(), _line);
    });

    test('every PLAN_ITEM_CLOSE_* reason forces a re-read', () async {
      for (final reason in const [
        'PLAN_ITEM_CLOSE_REQUESTED',
        'PLAN_ITEM_CLOSE_PALLETIZER_COMPLETING_PALLETS',
        'PLAN_ITEM_CLOSE_CONFIRMED',
        'PLAN_ITEM_CLOSE_REQUEST_CANCELLED',
        'PLAN_ITEM_CLOSE_REQUEST_INVALIDATED',
      ]) {
        final h = _Harness();
        await h.boot();
        h.repo.closeRequestReads.clear();
        await h.provider.refreshFromSseEvents([_frame('x', _line, reason)]);
        expect(h.readsFor(_line), hasLength(1), reason: reason);
      }
    });

    test(
      'a non-close frame inside the poll throttle does not re-read',
      () async {
        final h = _Harness();
        await h.boot();
        h.repo.closeRequestReads.clear();

        await h.provider.refreshFromSseEvents([
          _frame('e1', _line, 'LINE_TAKEOVER_REQUESTED'),
        ]);

        expect(h.readsFor(_line), isEmpty);
      },
    );

    test(
      'bootstrap (resume / reconnect / manual refresh) always re-reads',
      () async {
        final h = _Harness();
        await h.boot();
        h.repo.closeRequestReads.clear();

        await h.provider.refreshBootstrap();

        expect(h.readsFor(_line), hasLength(1));
      },
    );

    test('routine polls re-read at most every 20 seconds', () async {
      final h = _Harness();
      await h.boot();
      h.repo.closeRequestReads.clear();

      await h.provider.pollLineMonitoring();
      expect(h.readsFor(_line), isEmpty);

      h.now = h.now.add(PalletizingProvider.closeRequestPollInterval);
      await h.provider.pollLineMonitoring();
      expect(h.readsFor(_line), hasLength(1));
    });

    test('selecting a line re-reads its request', () async {
      final h = _Harness();
      await h.boot(sessionLines: const {_line, _otherLine});
      h.repo.closeRequestReads.clear();

      h.provider.selectLine(_otherLine);
      await pumpEventQueue();

      expect(h.readsFor(_otherLine), hasLength(1));
    });
  });

  group('pending read — reconciliation', () {
    test('a request for another palletizing line is never shown', () async {
      final h = _Harness();
      await h.boot();
      // The read for line 11 answers with a request of line 12.
      h.repo.activeCloseRequests[_line] = _waiting(lineId: _otherLine);

      await h.provider.refreshCloseRequest(_line);

      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.provider.getActiveCloseRequest(_otherLine), isNull);
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
    });

    test('a terminal status in the read is not shown', () async {
      final h = _Harness();
      await h.boot();
      h.repo.activeCloseRequests[_line] = closeRequest(
        lineId: _line,
        status: PlanItemCloseRequestStatus.confirmed,
      );

      await h.provider.refreshCloseRequest(_line);

      expect(h.provider.getActiveCloseRequest(_line), isNull);
    });

    test('a failed read keeps the last authoritative request', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.closeRequestReadErrors[_line] = ApiException.network();

      await h.provider.refreshCloseRequest(_line);

      expect(h.provider.getActiveCloseRequest(_line)?.closeRequestId, 3021);
      expect(h.provider.hasPendingCloseRequestNotices, isFalse);

      // The network is back: the same read recovers without user action.
      h.repo.closeRequestReadErrors.clear();
      h.repo.activeCloseRequests[_line] = closeRequest(
        lineId: _line,
        status: PlanItemCloseRequestStatus.palletizerCompletingPallets,
      );
      await h.provider.refreshCloseRequest(_line);
      expect(
        h.provider.getActiveCloseRequest(_line)?.isCompletingPallets,
        isTrue,
      );
    });

    for (final status in const [401, 403]) {
      test('$status PALLETIZER_SESSION_REQUIRED drops to PIN login and clears '
          'the request without a notice', () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        h.repo.closeRequestReadErrors[_line] = _api(
          'PALLETIZER_SESSION_REQUIRED',
          status,
        );

        await h.provider.refreshCloseRequest(_line);

        expect(h.provider.getActiveCloseRequest(_line), isNull);
        expect(h.provider.hasActivePalletizerSession(_line), isFalse);
        expect(h.auth.tokens.containsKey(_line), isFalse);
        expect(h.provider.getUiState(_line), LineUiState.needsPalletizerAuth);
        expect(h.provider.hasPendingCloseRequestNotices, isFalse);
      });
    }

    test('operator cancel: gone after the REST read, with the cancelled '
        'notice worded from the SSE reason', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.repo.activeCloseRequests.remove(_line);
      await h.provider.refreshFromSseEvents([
        _frame('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
      ]);

      expect(h.provider.getActiveCloseRequest(_line), isNull);
      final notices = h.provider.takeCloseRequestNotices();
      expect(notices, hasLength(1));
      expect(notices.single.lineId, _line);
      expect(notices.single.kind, CloseRequestNoticeKind.cancelled);
      expect(h.provider.takeCloseRequestNotices(), isEmpty);
    });

    test('invalidation: gone with the no-longer-valid notice', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.repo.activeCloseRequests.remove(_line);
      await h.provider.refreshFromSseEvents([
        _frame('i1', _line, 'PLAN_ITEM_CLOSE_REQUEST_INVALIDATED'),
      ]);

      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(
        h.provider.takeCloseRequestNotices().single.kind,
        CloseRequestNoticeKind.noLongerValid,
      );
    });

    test(
      'an SSE frame alone never removes the request — only the read does',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        // The backend still reports it active (the frame was for an older
        // transition, or arrived early).
        await h.provider.refreshFromSseEvents([
          _frame('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
        ]);

        expect(h.provider.getActiveCloseRequest(_line)?.closeRequestId, 3021);
        expect(h.provider.hasPendingCloseRequestNotices, isFalse);
      },
    );

    test('a request gone without any frame (missed SSE) gets the generic '
        'notice on the next poll', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.repo.activeCloseRequests.remove(_line);
      h.now = h.now.add(PalletizingProvider.closeRequestPollInterval);
      await h.provider.pollLineMonitoring();

      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(
        h.provider.takeCloseRequestNotices().single.kind,
        CloseRequestNoticeKind.noLongerValid,
      );
    });

    test('duplicate frames for one transition produce one notice', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.repo.activeCloseRequests.remove(_line);
      await h.provider.refreshFromSseEvents([
        _frame('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
      ]);
      await h.provider.refreshFromSseEvents([
        _frame('c2', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
      ]);

      expect(h.provider.takeCloseRequestNotices(), hasLength(1));
    });

    test('a replaced request (cancelled, then a new one) notifies once and '
        'shows the new id', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.repo.activeCloseRequests[_line] = _waiting(id: 3022);
      await h.provider.refreshFromSseEvents([
        _frame('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
        _frame('r1', _line, 'PLAN_ITEM_CLOSE_REQUESTED'),
      ]);

      expect(h.provider.getActiveCloseRequest(_line)?.closeRequestId, 3022);
      expect(
        h.provider.takeCloseRequestNotices().single.kind,
        CloseRequestNoticeKind.cancelled,
      );
    });

    test('logout clears the request without a notice', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      await h.provider.palletizerLogout(_line);

      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.provider.hasPendingCloseRequestNotices, isFalse);
    });

    test('a line switched off drops its request', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      h.serve([skewedLine(2, planItemId: 922, planProductId: 32)]);
      await h.provider.refreshBootstrap();

      expect(h.provider.isLineRendered(_line), isFalse);
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
    });

    test('only a WAITING request asks for the blocking dialog', () async {
      final h = _Harness();
      await h.boot(
        request: closeRequest(
          lineId: _line,
          status: PlanItemCloseRequestStatus.palletizerCompletingPallets,
        ),
      );

      expect(
        h.provider.getActiveCloseRequest(_line)?.isCompletingPallets,
        isTrue,
      );
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
    });

    test(
      'an active request keeps the 20 s cadence while SSE is connected',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        h.provider.onSseConnectionStateChanged(SseConnectionState.connected);

        expect(h.provider.pollCadence, PollCadence.closeRequestPending);

        h.repo.activeCloseRequests.remove(_line);
        await h.provider.refreshCloseRequest(_line);
        expect(h.provider.pollCadence, PollCadence.safety);
      },
    );
  });

  group('decisions (handoff §8 / §11 / §17 / §18)', () {
    test('"لا" calls more-pallets-remain once with the session token and '
        'moves the request to COMPLETING', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      final readsBefore = h.readsFor(_line).length;

      final outcome = await h.provider.reportMorePalletsRemain(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.applied);
      final call = h.repo.morePalletsCalls.single;
      expect(call.lineId, _line);
      expect(call.closeRequestId, _requestId);
      expect(call.sessionToken, 'token-$_line');
      expect(h.repo.confirmCalls, isEmpty);
      final active = h.provider.getActiveCloseRequest(_line)!;
      expect(active.isCompletingPallets, isTrue);
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
      expect(h.readsFor(_line).length, readsBefore + 1, reason: '§6 re-read');
      expect(h.provider.hasPendingCloseRequestNotices, isFalse);
      expect(h.provider.isCloseRequestDecisionInFlight(_line), isFalse);
    });

    test('pallet creation stays usable while COMPLETING and still targets '
        'the closing plan item', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      await h.provider.reportMorePalletsRemain(_line, _requestId);

      expect(h.provider.isPalletCreationBlocked(_line), isFalse);
      expect(h.provider.getUiState(_line), LineUiState.active);
      expect(
        h.provider.getCurrentPlanItemId(_line),
        h.provider.getActiveCloseRequest(_line)!.productionPlanItemId,
      );

      h.repo.createPalletError = _api(
        'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED',
      );
      await expectLater(
        h.provider.createPallet(
          lineId: _line,
          productTypeId: 31,
          quantity: 40,
          expectedPlanItemId: h.provider.getCurrentPlanItemId(_line)!,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(h.repo.createCalls.single.expectedPlanItemId, 912);
    });

    test('"نعم" calls confirm once, clears the request, queues the confirmed '
        'notice and re-reads the line state', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.lineStateLineIds.clear();

      final outcome = await h.provider.confirmAllPalletsRegistered(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.applied);
      final call = h.repo.confirmCalls.single;
      expect(call.closeRequestId, _requestId);
      expect(call.sessionToken, 'token-$_line');
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.repo.lineStateLineIds, contains(_line));
      expect(
        h.provider.takeCloseRequestNotices().single.kind,
        CloseRequestNoticeKind.confirmed,
      );
    });

    test(
      'the final confirmation from COMPLETING uses the same endpoint',
      () async {
        final h = _Harness();
        await h.boot(
          request: closeRequest(
            lineId: _line,
            status: PlanItemCloseRequestStatus.palletizerCompletingPallets,
          ),
        );

        final outcome = await h.provider.confirmAllPalletsRegistered(
          _line,
          _requestId,
        );

        expect(outcome, CloseDecisionOutcome.applied);
        expect(h.repo.confirmCalls, hasLength(1));
        expect(h.provider.getActiveCloseRequest(_line), isNull);
      },
    );

    test('a second tap while a decision is in flight sends nothing — for '
        'either answer', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      final gate = Completer<void>();
      h.repo.decisionGate = gate;

      final first = h.provider.confirmAllPalletsRegistered(_line, _requestId);
      expect(h.provider.isCloseRequestDecisionInFlight(_line), isTrue);
      expect(
        await h.provider.confirmAllPalletsRegistered(_line, _requestId),
        CloseDecisionOutcome.ignored,
      );
      expect(
        await h.provider.reportMorePalletsRemain(_line, _requestId),
        CloseDecisionOutcome.ignored,
      );

      gate.complete();
      expect(await first, CloseDecisionOutcome.applied);
      expect(h.repo.confirmCalls, hasLength(1));
      expect(h.repo.morePalletsCalls, isEmpty);
      expect(h.provider.isCloseRequestDecisionInFlight(_line), isFalse);
    });

    test(
      'a decision for a request that is no longer on screen sends nothing',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());

        expect(
          await h.provider.confirmAllPalletsRegistered(_line, 9999),
          CloseDecisionOutcome.ignored,
        );
        expect(
          await h.provider.confirmAllPalletsRegistered(_otherLine, _requestId),
          CloseDecisionOutcome.ignored,
        );
        expect(h.repo.confirmCalls, isEmpty);
      },
    );

    test(
      'a timeout is retried once and alreadyProcessed counts as success',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        // The first confirmation committed but its response was lost.
        h.repo.activeCloseRequests.remove(_line);
        h.repo.confirmResults.addAll([
          ApiException.timeout(),
          closeRequest(
            lineId: _line,
            status: PlanItemCloseRequestStatus.confirmed,
            alreadyProcessed: true,
          ),
        ]);

        final outcome = await h.provider.confirmAllPalletsRegistered(
          _line,
          _requestId,
        );

        expect(outcome, CloseDecisionOutcome.applied);
        expect(h.repo.confirmCalls, hasLength(2));
        expect(h.provider.getActiveCloseRequest(_line), isNull);
        expect(
          h.provider.takeCloseRequestNotices().single.kind,
          CloseRequestNoticeKind.confirmed,
        );
      },
    );

    test('network lost twice: the request stays pending with an inline error '
        'and a manual retry recovers', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.morePalletsResults.addAll([
        ApiException.network(),
        ApiException.network(),
      ]);

      final outcome = await h.provider.reportMorePalletsRemain(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.failed);
      expect(h.repo.morePalletsCalls, hasLength(2));
      expect(
        h.provider.getActiveCloseRequest(_line)?.isWaitingForDecision,
        isTrue,
      );
      expect(
        h.provider.getCloseRequestDecisionError(_line),
        ApiException.network().displayMessage,
      );
      expect(h.provider.hasPendingCloseRequestNotices, isFalse);

      // Retry by hand: the error clears and the decision lands.
      expect(
        await h.provider.reportMorePalletsRemain(_line, _requestId),
        CloseDecisionOutcome.applied,
      );
      expect(h.provider.getCloseRequestDecisionError(_line), isNull);
      expect(
        h.provider.getActiveCloseRequest(_line)?.isCompletingPallets,
        isTrue,
      );
    });

    test(
      'CONCURRENT_MODIFICATION is retried once, then explained inline',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        h.repo.confirmResults.addAll([
          _api('CONCURRENT_MODIFICATION'),
          _api('CONCURRENT_MODIFICATION'),
        ]);

        final outcome = await h.provider.confirmAllPalletsRegistered(
          _line,
          _requestId,
        );

        expect(outcome, CloseDecisionOutcome.failed);
        expect(h.repo.confirmCalls, hasLength(2));
        expect(
          h.provider.getCloseRequestDecisionError(_line),
          PlanItemCloseRequestStrings.conflictRetry,
        );
        expect(h.provider.getActiveCloseRequest(_line), isNotNull);
      },
    );

    test('a paused line keeps the request and says so — no retry', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.confirmResults.add(_api('THERMOFORMING_LINE_PAUSED'));

      final outcome = await h.provider.confirmAllPalletsRegistered(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.failed);
      expect(h.repo.confirmCalls, hasLength(1));
      expect(
        h.provider.getCloseRequestDecisionError(_line),
        'الخط متوقف من الإدارة',
      );
      expect(h.provider.getActiveCloseRequest(_line), isNotNull);
    });

    test('a roll / plan rule rejected by the close shows the backend message '
        'and keeps the request', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.confirmResults.add(
        ApiException(
          code: 'MOUNTED_ROLL_RESOLUTION_REQUIRED_FOR_ITEM_CLOSE',
          message: 'يجب حسم الرول المركّب قبل إنهاء البند',
          statusCode: 409,
        ),
      );

      await h.provider.confirmAllPalletsRegistered(_line, _requestId);

      expect(
        h.provider.getCloseRequestDecisionError(_line),
        'يجب حسم الرول المركّب قبل إنهاء البند',
      );
      expect(h.provider.getActiveCloseRequest(_line), isNotNull);
    });

    test('NOT_ACTIVE (operator cancelled at the same moment) removes the '
        'request with the cancelled wording', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      // The cancel frame arrives while the read fails, so the request is
      // still on screen when the palletizer taps.
      h.repo.activeCloseRequests.remove(_line);
      h.repo.closeRequestReadErrors[_line] = ApiException.network();
      await h.provider.refreshFromSseEvents([
        _frame('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED'),
      ]);
      expect(h.provider.getActiveCloseRequest(_line), isNotNull);
      h.repo.closeRequestReadErrors.clear();

      final outcome = await h.provider.confirmAllPalletsRegistered(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.requestGone);
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(
        h.provider.takeCloseRequestNotices().single.kind,
        CloseRequestNoticeKind.cancelled,
      );
    });

    test('STALE (invalidated during the decision) removes the request with '
        'the no-longer-valid notice', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.activeCloseRequests.remove(_line);
      h.repo.confirmResults.add(
        ApiException(
          code: 'THERMOFORMING_PLAN_ITEM_CLOSE_REQUEST_STALE',
          message: 'تغيّرت حالة الخط بعد إرسال طلب إنهاء البند',
          details: const {
            'closeRequestId': 3021,
            'invalidationReason': 'MOUNTED_ROLL_CHANGED',
          },
          statusCode: 409,
        ),
      );

      final outcome = await h.provider.confirmAllPalletsRegistered(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.requestGone);
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      final notices = h.provider.takeCloseRequestNotices();
      expect(notices, hasLength(1));
      expect(notices.single.kind, CloseRequestNoticeKind.noLongerValid);
    });

    test('an expired session on a decision drops to PIN login', () async {
      final h = _Harness();
      await h.boot(request: _waiting());
      h.repo.morePalletsResults.add(_api('PALLETIZER_SESSION_REQUIRED', 401));

      final outcome = await h.provider.reportMorePalletsRemain(
        _line,
        _requestId,
      );

      expect(outcome, CloseDecisionOutcome.sessionLost);
      expect(h.provider.getActiveCloseRequest(_line), isNull);
      expect(h.provider.getUiState(_line), LineUiState.needsPalletizerAuth);
    });

    test(
      'a missing stored token sends nothing and drops to PIN login',
      () async {
        final h = _Harness();
        await h.boot(request: _waiting());
        h.auth.tokens.remove(_line);

        final outcome = await h.provider.confirmAllPalletsRegistered(
          _line,
          _requestId,
        );

        expect(outcome, CloseDecisionOutcome.sessionLost);
        expect(h.repo.confirmCalls, isEmpty);
        expect(h.provider.getActiveCloseRequest(_line), isNull);
      },
    );

    test('a slow read captured before a decision can never undo it', () async {
      final h = _Harness();
      await h.boot(request: _waiting());

      // A read goes out and captures WAITING, but answers late.
      final gate = Completer<void>();
      h.repo.readGate = gate;
      final slowRead = h.provider.refreshCloseRequest(_line);
      await pumpEventQueue();
      h.repo.readGate = null;

      // "لا" lands first.
      final decision = h.provider.reportMorePalletsRemain(_line, _requestId);
      await pumpEventQueue();
      expect(
        h.provider.getActiveCloseRequest(_line)?.isCompletingPallets,
        isTrue,
      );

      // The overtaken WAITING answer arrives and is dropped.
      gate.complete();
      await slowRead;
      expect(await decision, CloseDecisionOutcome.applied);
      expect(
        h.provider.getActiveCloseRequest(_line)?.isCompletingPallets,
        isTrue,
      );
      expect(h.provider.firstLineAwaitingCloseDecision(), isNull);
    });
  });
}
