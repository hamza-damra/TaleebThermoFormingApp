// Tests for the SSE frame parser and the `palletizing-lines-changed` event
// model. Both are pure (no IO, no timers), so these run fast and
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
}
