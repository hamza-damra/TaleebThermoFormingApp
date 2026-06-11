// ManagerAnnouncementNotifier — sanitized urgent manager announcements.
//
// Pure provider-level tests with in-memory fakes — no real network / SSE.
// They pin the cross-line contract from
// docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md:
//   * fetch pending for every operating lineId;
//   * the same announcement on two lines shows once (dedupe by id);
//   * acknowledge acks every operating lineId (idempotent);
//   * a failed ack keeps the notice open with retry text; a retry closes it;
//   * an SSE nudge triggers a pending fetch;
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

ManagerAnnouncement _ann(int id, {DateTime? createdAt}) => ManagerAnnouncement(
      id: id,
      targetDomain: 'THERMOFORMING',
      title: 'ملاحظة عاجلة من المدير',
      message: 'أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.',
      createdAt: createdAt,
      createdAtDisplay: '',
      priority: 'URGENT',
    );

({
  ManagerAnnouncementNotifier notifier,
  _FakeRepo repo,
  StreamController<UrgentManagerAnnouncementEvent> sse,
}) _build({required List<int> lineIds}) {
  final repo = _FakeRepo();
  final sse = StreamController<UrgentManagerAnnouncementEvent>.broadcast();
  final notifier = ManagerAnnouncementNotifier(
    repo,
    lineIdsSupplier: () => lineIds,
    announcements: sse.stream,
    debounce: const Duration(milliseconds: 10),
  );
  return (notifier: notifier, repo: repo, sse: sse);
}

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

      // Wait past the (test) debounce window + microtasks.
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(t.repo.pendingCallCount, greaterThanOrEqualTo(1));
      expect(t.notifier.current!.id, 3);
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
        'priority': 'URGENT',
        // A future backend bug must never leak these — there is nowhere to
        // parse them into.
        'messageBody': 'SECRET real manager message body',
        'senderDisplayName': 'Real Manager Name',
      });

      expect(model.id, 1);
      expect(model.createdAtDisplay, contains('مساءً'));
      expect(model.createdAt, DateTime.parse('2026-06-10T15:10:00Z'));
      // None of the model's surfaced fields carry the secret content.
      expect(model.title, isNot(contains('Real Manager Name')));
      expect(model.message, isNot(contains('SECRET')));
    });
  });
}
