// Tests for the SSE frame parser and the two event models it feeds —
// `palletizing-lines-changed` and the sanitized `urgent-manager-announcement`
// nudge. All are pure (no IO, no timers), so these run fast and
// deterministically.

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/core/services/sse_frame_parser.dart';

void main() {
  group('SseFrameParser', () {
    test('parses a complete frame in one chunk', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk(
        'event: palletizing-lines-changed\ndata: {"eventId":"a"}\n\n',
      );
      expect(frames, hasLength(1));
      expect(frames.single.event, 'palletizing-lines-changed');
      expect(frames.single.data, '{"eventId":"a"}');
      expect(frames.single.isComment, isFalse);
    });

    test('reassembles a frame split across two chunks', () {
      final parser = SseFrameParser();
      final first = parser.addChunk('event: connected\ndata: {"sta');
      expect(first, isEmpty); // line not yet terminated

      final second = parser.addChunk('tus":"connected"}\n\n');
      expect(second, hasLength(1));
      expect(second.single.event, 'connected');
      expect(second.single.data, '{"status":"connected"}');
    });

    test('joins multiple data lines with a newline', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk('data: line1\ndata: line2\n\n');
      expect(frames.single.data, 'line1\nline2');
    });

    test('surfaces a :ping comment as an isComment frame', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk(':ping\n');
      expect(frames, hasLength(1));
      expect(frames.single.isComment, isTrue);
    });

    test('handles CRLF line endings', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk(
        'event: connected\r\ndata: {"status":"connected"}\r\n\r\n',
      );
      expect(frames, hasLength(1));
      expect(frames.single.event, 'connected');
      expect(frames.single.data, '{"status":"connected"}');
    });

    test('strips exactly one leading space from a field value', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk('data:  two-spaces\n\n');
      expect(frames.single.data, ' two-spaces');
    });

    test('does not dispatch an empty frame for a blank line with no fields',
        () {
      final parser = SseFrameParser();
      final frames = parser.addChunk('\n\n\n');
      expect(frames, isEmpty);
    });

    test('ignores unknown fields without throwing', () {
      final parser = SseFrameParser();
      final frames = parser.addChunk('retry: 5000\ndata: x\n\n');
      expect(frames.single.data, 'x');
    });

    test('reset drops buffered partial state', () {
      final parser = SseFrameParser();
      parser.addChunk('data: partial');
      parser.reset();
      final frames = parser.addChunk('-tail\n\n');
      // The buffered "data: partial" was dropped; "-tail" is an orphan field
      // name with no recognised meaning, so no business frame is produced.
      expect(frames.every((f) => f.data != 'partial-tail'), isTrue);
    });
  });

  group('PalletizingAppSseEvent.tryParse', () {
    test('parses a well-formed payload', () {
      final event = PalletizingAppSseEvent.tryParse(
        '{"type":"LINE_STATE_CHANGED","reason":"PALLET_CREATED",'
        '"palletizingLineId":1,"version":123,"eventId":"abc",'
        '"occurredAt":"2026-05-17T05:40:00.000+03:00"}',
      );
      expect(event, isNotNull);
      expect(event!.eventId, 'abc');
      expect(event.reason, 'PALLET_CREATED');
      expect(event.palletizingLineId, 1);
      expect(event.version, 123);
      expect(event.occurredAt, isNotNull);
    });

    test('parses a UTC "Z" occurredAt to the same instant as the old offset', () {
      // The backend switched occurredAt from "+03:00" to UTC "Z". Both spellings
      // denote the same instant and must stay interchangeable, because cached
      // and replayed frames can still carry the old form.
      final utc = PalletizingAppSseEvent.tryParse(
        '{"eventId":"a","occurredAt":"2026-05-17T20:09:00Z"}',
      );
      final offset = PalletizingAppSseEvent.tryParse(
        '{"eventId":"b","occurredAt":"2026-05-17T23:09:00.000+03:00"}',
      );
      expect(utc!.occurredAt!.isAtSameMomentAs(offset!.occurredAt!), isTrue);
    });

    test('parses a frame with no thermoformingLineId', () {
      // The key is omitted entirely unless the backend knows the value.
      final event = PalletizingAppSseEvent.tryParse(
        '{"eventId":"x","reason":"PALLET_CREATED"}',
      );
      expect(event, isNotNull);
      expect(event!.thermoformingLineId, isNull);
    });

    test('returns null on malformed JSON', () {
      expect(PalletizingAppSseEvent.tryParse('{not json'), isNull);
    });

    test('returns null when eventId is missing', () {
      expect(PalletizingAppSseEvent.tryParse('{"reason":"X"}'), isNull);
    });

    test('returns null when eventId is empty', () {
      expect(PalletizingAppSseEvent.tryParse('{"eventId":""}'), isNull);
    });

    test('returns null for a non-object payload', () {
      expect(PalletizingAppSseEvent.tryParse('[1,2,3]'), isNull);
    });

    test('tolerates a string-typed numeric line id', () {
      final event =
          PalletizingAppSseEvent.tryParse('{"eventId":"x","palletizingLineId":"2"}');
      expect(event?.palletizingLineId, 2);
    });

    test('keeps the event when an optional field has an unexpected type', () {
      // version is a string here — coerced, not fatal.
      final event = PalletizingAppSseEvent.tryParse(
        '{"eventId":"x","version":"notanumber"}',
      );
      expect(event, isNotNull);
      expect(event!.version, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // UrgentManagerAnnouncementEvent — the sanitized nudge, now with `action`.
  //
  // Announcements are timed, so one announcementId produces a nudge on every
  // lifecycle step. `eventType` stays frozen at `..._CREATED` for all of them,
  // so `action` is the only field that names the step. The app must never
  // branch on it — these tests pin that it *parses*, not that it dispatches.
  // ───────────────────────────────────────────────────────────────────────

  group('UrgentManagerAnnouncementEvent.tryParse', () {
    String frame(String action) => '{"eventType":'
        '"URGENT_MANAGER_ANNOUNCEMENT_CREATED","announcementId":99,'
        '"targetDomain":"THERMOFORMING","priority":"URGENT","action":"$action"}';

    test('parses every documented action value', () {
      for (final action in ['CREATED', 'UPDATED', 'DEACTIVATED', 'DELETED']) {
        final event = UrgentManagerAnnouncementEvent.tryParse(frame(action));
        expect(event, isNotNull, reason: action);
        expect(event!.action, action);
        // The legacy literal is frozen — it never tracks the action.
        expect(event.eventType, 'URGENT_MANAGER_ANNOUNCEMENT_CREATED');
        expect(event.announcementId, 99);
        expect(event.targetDomain, 'THERMOFORMING');
        expect(event.priority, 'URGENT');
      }
    });

    test('parses a legacy frame with no action key (means CREATED)', () {
      final event = UrgentManagerAnnouncementEvent.tryParse(
        '{"eventType":"URGENT_MANAGER_ANNOUNCEMENT_CREATED",'
        '"announcementId":99,"targetDomain":"THERMOFORMING","priority":"URGENT"}',
      );
      expect(event, isNotNull);
      expect(event!.action, isNull);
      expect(event.announcementId, 99);
    });

    test('keeps an unknown future action verbatim rather than rejecting it', () {
      // Refetching is always the safe response, so an unrecognised value must
      // still produce an event.
      final event = UrgentManagerAnnouncementEvent.tryParse(frame('ARCHIVED'));
      expect(event, isNotNull);
      expect(event!.action, 'ARCHIVED');
    });

    test('ignores a non-string action instead of throwing', () {
      final event = UrgentManagerAnnouncementEvent.tryParse(
        '{"announcementId":99,"action":7}',
      );
      expect(event, isNotNull);
      expect(event!.action, isNull);
    });

    test('never carries a message body or sender, even if one is sent', () {
      // Privacy: the type has nowhere to parse these into.
      final event = UrgentManagerAnnouncementEvent.tryParse(
        '{"announcementId":99,"action":"CREATED",'
        '"messageBody":"SECRET","senderDisplayName":"Real Manager"}',
      );
      expect(event, isNotNull);
      expect(event.toString(), isNot(contains('SECRET')));
      expect(event.toString(), isNot(contains('Real Manager')));
    });

    test('returns null on malformed JSON and on a non-object payload', () {
      expect(UrgentManagerAnnouncementEvent.tryParse('{not json'), isNull);
      expect(UrgentManagerAnnouncementEvent.tryParse('[1,2,3]'), isNull);
    });
  });
}
