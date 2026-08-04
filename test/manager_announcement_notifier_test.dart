// ManagerAnnouncementNotifier — sanitized urgent manager announcements.
//
// Pure provider-level tests with in-memory fakes — no real network / SSE.
// They pin the cross-line contract from
// docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md:
//   * fetch pending for every operating lineId;
//   * the same announcement on two lines shows once (dedupe by id);
//   * acknowledge acks every operating lineId (idempotent);
//   * a failed ack keeps the notice open with retry text; a retry closes it;
//   * an SSE nudge triggers a pending fetch — for every `action` value;
//   * every SSE (re)connect triggers a pending fetch;
//   * a timed notice clears on its own `expiresAt`, online and offline;
//   * after ack-all, a later refresh (tab switch / resume) never re-shows it;
//   * the DTO parser never surfaces a real messageBody / senderDisplayName.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/data/models/manager_announcement_model.dart';
import 'package:taleeb_thermoforming/domain/entities/manager_announcement.dart';
import 'package:taleeb_thermoforming/domain/repositories/palletizing_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/manager_announcement_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────
// Fakes
// ─────────────────────────────────────────────────────────────────────────

/// Implements only the two announcement endpoints; everything else routes to
/// [noSuchMethod] (the notifier never touches them). Models backend semantics:
/// a successful ack removes the announcement from that line's pending list, so
/// a later fetch genuinely returns nothing.
class _FakeRepo implements PalletizingRepository {
  final Map<int, List<ManagerAnnouncement>> pendingByLine = {};
  final Set<int> failPendingForLine = {};
  final Set<int> failAckForLine = {};
  final List<({int announcementId, int lineId})> ackCalls = [];
  int pendingCallCount = 0;

  @override
  Future<List<ManagerAnnouncement>> getPendingUrgentAnnouncements(
    int lineId,
  ) async {
    pendingCallCount++;
    if (failPendingForLine.contains(lineId)) {
      throw ApiException(code: 'BOOM', message: 'pending failed');
    }
    return List<ManagerAnnouncement>.from(pendingByLine[lineId] ?? const []);
  }

  @override
  Future<void> ackUrgentAnnouncement({
    required int announcementId,
    required int lineId,
  }) async {
    if (failAckForLine.contains(lineId)) {
      throw ApiException(code: 'BOOM', message: 'ack failed');
    }
    ackCalls.add((announcementId: announcementId, lineId: lineId));
    pendingByLine[lineId]?.removeWhere((a) => a.id == announcementId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// ─────────────────────────────────────────────────────────────────────────
// Builders
// ─────────────────────────────────────────────────────────────────────────

ManagerAnnouncement _ann(int id, {DateTime? createdAt, DateTime? expiresAt}) =>
    ManagerAnnouncement(
      id: id,
      targetDomain: 'THERMOFORMING',
      title: 'ملاحظة عاجلة من المدير',
      message: 'أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.',
      createdAt: createdAt,
      createdAtDisplay: '',
      priority: 'URGENT',
      expiresAt: expiresAt,
    );

({
  ManagerAnnouncementNotifier notifier,
  _FakeRepo repo,
  StreamController<UrgentManagerAnnouncementEvent> sse,
  StreamController<SseConnectionState> connection,
}) _build({required List<int> lineIds}) {
  final repo = _FakeRepo();
  final sse = StreamController<UrgentManagerAnnouncementEvent>.broadcast();
  final connection = StreamController<SseConnectionState>.broadcast();
  final notifier = ManagerAnnouncementNotifier(
    repo,
    lineIdsSupplier: () => lineIds,
    announcements: sse.stream,
    connectionStates: connection.stream,
    debounce: const Duration(milliseconds: 10),
  );
  return (notifier: notifier, repo: repo, sse: sse, connection: connection);
}

/// Waits past the (test) debounce window plus the microtask drain.
Future<void> _settle([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('ManagerAnnouncementNotifier — fetch', () {
    test('fetches pending for every operating lineId', () async {
      final t = _build(lineIds: [101, 102]);
      t.repo.pendingByLine[101] = [_ann(1)];
      t.repo.pendingByLine[102] = [_ann(2)];

      await t.notifier.refresh();

      expect(t.repo.pendingCallCount, 2);
      expect(t.notifier.pendingCount, 2);
      // Oldest-first; equal (null) timestamps tiebreak by id ascending.
      expect(t.notifier.current!.id, 1);
    });

    test('the same announcement on two lines shows once (dedupe by id)',
        () async {
      final t = _build(lineIds: [101, 102]);
      t.repo.pendingByLine[101] = [_ann(7)];
      t.repo.pendingByLine[102] = [_ann(7)];

      await t.notifier.refresh();

      expect(t.notifier.pendingCount, 1);
      expect(t.notifier.current!.id, 7);
    });

    test('no operating lineIds → fetch is a silent no-op (no error)', () async {
      final t = _build(lineIds: []);

      await t.notifier.refresh();

      expect(t.repo.pendingCallCount, 0);
      expect(t.notifier.current, isNull);
      expect(t.notifier.error, isNull);
    });

    test('total fetch failure keeps the prior notice rather than hiding it',
        () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(4)];
      await t.notifier.refresh();
      expect(t.notifier.current!.id, 4);

      // Now every line errors — the notice must stay visible.
      t.repo.failPendingForLine.add(101);
      await t.notifier.refresh();
      expect(t.notifier.current!.id, 4);
    });
  });

  group('ManagerAnnouncementNotifier — acknowledge (all operating lines)', () {
    test('acks the announcement for every operating lineId, then closes',
        () async {
      final t = _build(lineIds: [101, 102]);
      t.repo.pendingByLine[101] = [_ann(5)];
      t.repo.pendingByLine[102] = [_ann(5)];
      await t.notifier.refresh();

      await t.notifier.acknowledgeCurrent();

      expect(t.repo.ackCalls.map((c) => c.lineId).toSet(), {101, 102});
      expect(t.repo.ackCalls.every((c) => c.announcementId == 5), isTrue);
      expect(t.notifier.current, isNull);
      expect(t.notifier.error, isNull);
      expect(t.notifier.acking, isFalse);
    });

    test('a failed ack keeps the notice open with retry text; a retry closes it',
        () async {
      final t = _build(lineIds: [101, 102]);
      t.repo.pendingByLine[101] = [_ann(9)];
      t.repo.pendingByLine[102] = [_ann(9)];
      t.repo.failAckForLine.add(102); // one line fails the first time
      await t.notifier.refresh();

      await t.notifier.acknowledgeCurrent();
      expect(t.notifier.current, isNotNull); // still showing
      expect(t.notifier.error, ManagerAnnouncementNotifier.ackErrorMessage);
      expect(t.notifier.acking, isFalse);

      // Operator retries; the failing line now succeeds.
      t.repo.failAckForLine.clear();
      await t.notifier.acknowledgeCurrent();
      expect(t.notifier.current, isNull);
      expect(t.notifier.error, isNull);
    });

    test('after ack-all, a later refresh (tab switch / resume) does not re-show',
        () async {
      final t = _build(lineIds: [101, 102]);
      t.repo.pendingByLine[101] = [_ann(11)];
      t.repo.pendingByLine[102] = [_ann(11)];
      await t.notifier.refresh();
      await t.notifier.acknowledgeCurrent();
      expect(t.notifier.current, isNull);

      // Simulate a re-fetch triggered by switching machine tabs / resume.
      await t.notifier.refresh();
      expect(t.notifier.current, isNull);
    });
  });

  group('ManagerAnnouncementNotifier — SSE nudge', () {
    test('an urgent-manager-announcement nudge triggers a pending fetch',
        () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(3)];

      t.sse.add(const UrgentManagerAnnouncementEvent(
        eventType: 'URGENT_MANAGER_ANNOUNCEMENT_CREATED',
        announcementId: 3,
        targetDomain: 'THERMOFORMING',
        priority: 'URGENT',
      ));

      await _settle();

      expect(t.repo.pendingCallCount, greaterThanOrEqualTo(1));
      expect(t.notifier.current!.id, 3);
    });

    test('a nudge of each action value triggers exactly one refetch', () async {
      // `eventType` is frozen at `..._CREATED` for every step, so the action is
      // the only thing that varies — and none of them may change the response.
      for (final action in [
        'CREATED',
        'UPDATED',
        'DEACTIVATED',
        'DELETED',
        'ARCHIVED', // unknown future value — refetch anyway
        null, // older backend — treat as CREATED
      ]) {
        final t = _build(lineIds: [101]);
        t.repo.pendingByLine[101] = [_ann(3)];

        t.sse.add(UrgentManagerAnnouncementEvent(
          eventType: 'URGENT_MANAGER_ANNOUNCEMENT_CREATED',
          announcementId: 3,
          targetDomain: 'THERMOFORMING',
          priority: 'URGENT',
          action: action,
        ));
        await _settle();

        // One line × one fetch — the nudge is never inspected, never dropped.
        expect(t.repo.pendingCallCount, 1, reason: 'action: $action');
        expect(t.notifier.current!.id, 3, reason: 'action: $action');
        t.notifier.dispose();
      }
    });

    test('a burst of nudges collapses into a single fetch', () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(3)];

      for (final action in ['CREATED', 'UPDATED', 'DEACTIVATED']) {
        t.sse.add(UrgentManagerAnnouncementEvent(
          announcementId: 3,
          action: action,
        ));
      }
      await _settle();

      expect(t.repo.pendingCallCount, 1);
    });
  });

  group('ManagerAnnouncementNotifier — SSE (re)connect', () {
    test('a transition to connected triggers a pending fetch', () async {
      // Reconciles nudges missed while the stream was down — handoff §4.5.
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(8)];

      t.connection.add(SseConnectionState.connected);
      await _settle();

      expect(t.repo.pendingCallCount, 1);
      expect(t.notifier.current!.id, 8);
    });

    test('non-connected transitions do not fetch', () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(8)];

      t.connection
        ..add(SseConnectionState.connecting)
        ..add(SseConnectionState.reconnecting)
        ..add(SseConnectionState.disconnected);
      await _settle();

      expect(t.repo.pendingCallCount, 0);
      expect(t.notifier.current, isNull);
    });

    test('a reconnect plus the nudges it replays collapse into one fetch',
        () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(8)];

      t.connection.add(SseConnectionState.connected);
      t.sse.add(const UrgentManagerAnnouncementEvent(announcementId: 8));
      await _settle();

      expect(t.repo.pendingCallCount, 1);
    });
  });

  group('ManagerAnnouncementNotifier — expiry', () {
    test('a notice with a near-future expiresAt clears without another nudge',
        () async {
      final t = _build(lineIds: [101]);
      final expiresAt = DateTime.now().add(const Duration(milliseconds: 60));
      t.repo.pendingByLine[101] = [_ann(12, expiresAt: expiresAt)];

      await t.notifier.refresh();
      expect(t.notifier.current!.id, 12);

      // The backend now excludes the expired row; the armed timer re-fetches.
      t.repo.pendingByLine[101] = [];
      await _settle(1200); // deadline + the 1s grace

      expect(t.notifier.current, isNull);
      expect(t.repo.pendingCallCount, 2); // the refresh + the expiry refetch
    });

    test('a null expiresAt never expires and arms no timer', () async {
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [_ann(13)];

      await t.notifier.refresh();
      await _settle(1200);

      expect(t.notifier.current!.id, 13);
      expect(t.repo.pendingCallCount, 1); // no expiry refetch fired
    });

    test('offline at the deadline still clears the expired notice', () async {
      final t = _build(lineIds: [101]);
      final expiresAt = DateTime.now().add(const Duration(milliseconds: 60));
      t.repo.pendingByLine[101] = [_ann(14, expiresAt: expiresAt)];

      await t.notifier.refresh();
      expect(t.notifier.current!.id, 14);

      // Every line unreachable when the deadline fires — the local clock has to
      // carry the guarantee.
      t.repo.failPendingForLine.add(101);
      await _settle(1200);

      expect(t.notifier.current, isNull);
    });

    test('a failed fetch keeps a notice that has NOT expired', () async {
      // Guards the offline sweep against hiding an unacked, still-live notice.
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [
        _ann(15, expiresAt: DateTime.now().add(const Duration(hours: 2))),
      ];

      await t.notifier.refresh();
      t.repo.failPendingForLine.add(101);
      await t.notifier.refresh();

      expect(t.notifier.current!.id, 15);
    });

    test('an already-expired row from the server does not spin the timer',
        () async {
      // Clock skew: the backend still lists it, our clock says it is past.
      // Re-arming at zero would loop fetch → fire → fetch forever.
      final t = _build(lineIds: [101]);
      t.repo.pendingByLine[101] = [
        _ann(16, expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
      ];

      await t.notifier.refresh();
      await _settle(1200);

      expect(t.repo.pendingCallCount, 1); // the initial refresh only
      expect(t.notifier.current!.id, 16); // REST is authoritative — still shown
    });
  });

  group('ManagerAnnouncementModel — expiry fields', () {
    test('parses expiresAt / expiresAtDisplay', () {
      final model = ManagerAnnouncementModel.fromJson({
        'id': 99,
        'targetDomain': 'THERMOFORMING',
        'title': 'ملاحظة عاجلة من المدير',
        'message': 'أرسل المدير ملاحظة عاجلة للمشغل.',
        'createdAt': '2026-07-31T09:00:00.000Z',
        'createdAtDisplay': '2026-07-31، 12:00 مساءً',
        'expiresAt': '2026-07-31T11:00:00.000Z',
        'expiresAtDisplay': '2026-07-31، 02:00 مساءً',
        'priority': 'URGENT',
      });

      expect(model.expiresAt, DateTime.parse('2026-07-31T11:00:00.000Z'));
      expect(model.expiresAtDisplay, '2026-07-31، 02:00 مساءً');
    });

    test('a legacy row with the keys absent never expires', () {
      final model = ManagerAnnouncementModel.fromJson({
        'id': 99,
        'targetDomain': 'THERMOFORMING',
        'title': 'ملاحظة عاجلة من المدير',
        'message': 'أرسل المدير ملاحظة عاجلة للمشغل.',
        'createdAt': '2026-07-31T09:00:00.000Z',
        'createdAtDisplay': '2026-07-31، 12:00 مساءً',
        'priority': 'URGENT',
      });

      expect(model.expiresAt, isNull);
      expect(model.expiresAtDisplay, isNull);
      expect(model.isExpiredAt(DateTime(2099)), isFalse);
    });

    test('explicit nulls parse to null rather than throwing', () {
      final model = ManagerAnnouncementModel.fromJson({
        'id': 99,
        'targetDomain': 'THERMOFORMING',
        'title': '',
        'message': '',
        'createdAt': null,
        'createdAtDisplay': null,
        'expiresAt': null,
        'expiresAtDisplay': null,
        'priority': 'URGENT',
      });

      expect(model.expiresAt, isNull);
      expect(model.expiresAtDisplay, isNull);
    });

    test('isExpiredAt is boundary-exclusive, matching `expiresAt > now`', () {
      final deadline = DateTime.parse('2026-07-31T11:00:00.000Z');
      final ann = _ann(1, expiresAt: deadline);

      expect(ann.isExpiredAt(deadline.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(ann.isExpiredAt(deadline), isTrue); // exactly at the boundary
      expect(ann.isExpiredAt(deadline.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('ManagerAnnouncementModel — privacy', () {
    test('fromJson ignores messageBody / senderDisplayName if accidentally sent',
        () {
      final model = ManagerAnnouncementModel.fromJson({
        'id': 1,
        'targetDomain': 'THERMOFORMING',
        'title': 'ملاحظة عاجلة من المدير',
        'message': 'أرسل المدير ملاحظة عاجلة للمشغل.',
        'createdAt': '2026-06-10T15:10:00Z',
        'createdAtDisplay': '2026-06-10، 06:10 مساءً',
        'expiresAt': '2026-06-10T17:10:00Z',
        'expiresAtDisplay': '2026-06-10، 08:10 مساءً',
        'priority': 'URGENT',
        // A future backend bug must never leak these — there is nowhere to
        // parse them into.
        'messageBody': 'SECRET real manager message body',
        'senderDisplayName': 'Real Manager Name',
      });

      expect(model.id, 1);
      expect(model.createdAtDisplay, contains('مساءً'));
      expect(model.createdAt, DateTime.parse('2026-06-10T15:10:00Z'));
      // None of the model's surfaced fields carry the secret content — the two
      // new expiry fields included.
      expect(model.title, isNot(contains('Real Manager Name')));
      expect(model.message, isNot(contains('SECRET')));
      expect(model.expiresAtDisplay, isNot(contains('SECRET')));
      expect(model.expiresAtDisplay, isNot(contains('Real Manager Name')));
    });
  });
}
