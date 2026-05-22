// SSE client + RefreshCoordinator tests.
//
// The RefreshCoordinator tests drive a hand-written `_FakeSseClient` (no IO).
// The SseClient tests drive the real client through a fake Dio
// `HttpClientAdapter` so the frame routing / dedupe / reconnect paths are
// exercised end to end without a network.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/core/services/refresh_coordinator.dart';
import 'package:taleeb_thermoforming/core/services/sse_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';

// ─────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────

/// A fully controllable stand-in for [SseClient] used by the coordinator
/// tests. Implements the concrete class as an interface.
class _FakeSseClient implements SseClient {
  final _stateController = StreamController<SseConnectionState>.broadcast();
  final _eventController = StreamController<PalletizingAppSseEvent>.broadcast();
  final SseConnectionState _state = SseConnectionState.disconnected;
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<SseConnectionState> get connectionState => _stateController.stream;
  @override
  Stream<PalletizingAppSseEvent> get events => _eventController.stream;
  @override
  SseConnectionState get currentState => _state;
  @override
  String get path => '/api/v1/palletizing-line/app-events';

  @override
  void start() => startCount++;
  @override
  void stop() => stopCount++;
  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _eventController.close();
  }

  void emitEvent(PalletizingAppSseEvent e) => _eventController.add(e);
}

/// AuthLocalStorage that never touches `flutter_secure_storage`.
class _FakeAuthStorage extends AuthLocalStorage {
  @override
  Future<String?> getDeviceKey() async => 'test-device-key';
}

/// Fake Dio adapter that returns a streamed `text/event-stream` response the
/// test feeds byte-by-byte.
class _FakeSseAdapter implements HttpClientAdapter {
  final List<StreamController<Uint8List>> controllers = [];
  int fetchCount = 0;

  StreamController<Uint8List> get latest => controllers.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    final controller = StreamController<Uint8List>();
    controllers.add(controller);
    return ResponseBody(
      controller.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Lets pending microtasks + the fake adapter's async `fetch` settle.
Future<void> _pump([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

PalletizingAppSseEvent _event(String id, {int? line}) =>
    PalletizingAppSseEvent(eventId: id, palletizingLineId: line);

// ─────────────────────────────────────────────────────────────────────────
// RefreshCoordinator
// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('RefreshCoordinator', () {
    late _FakeSseClient sse;
    late RefreshCoordinator coordinator;
    late int pollCalls;
    late List<int?> eventRefreshes;

    RefreshCoordinator build({Duration poll = const Duration(seconds: 30)}) {
      return RefreshCoordinator(
        sseClient: sse,
        onPoll: () async => pollCalls++,
        onEventRefresh: (lineId) async => eventRefreshes.add(lineId),
        nextInterval: () => poll,
        debounce: const Duration(milliseconds: 30),
      );
    }

    setUp(() {
      sse = _FakeSseClient();
      pollCalls = 0;
      eventRefreshes = [];
    });

    tearDown(() async {
      await coordinator.dispose();
    });

    test('start() is idempotent — no duplicate SSE client / timers', () {
      coordinator = build()..start()..start()..start();
      expect(sse.startCount, 1);
    });

    test('an SSE event triggers one debounced refresh', () async {
      coordinator = build()..start();
      sse.emitEvent(_event('a', line: 1));
      expect(eventRefreshes, isEmpty); // still within the debounce window
      await _pump(60);
      expect(eventRefreshes, [1]);
    });

    test('a burst of events collapses into a single refresh', () async {
      coordinator = build()..start();
      sse.emitEvent(_event('a', line: 1));
      sse.emitEvent(_event('b', line: 1));
      sse.emitEvent(_event('c', line: 1));
      await _pump(60);
      expect(eventRefreshes, [1]);
    });

    test('events for two different lines escalate to a full refresh', () async {
      coordinator = build()..start();
      sse.emitEvent(_event('a', line: 1));
      sse.emitEvent(_event('b', line: 2));
      await _pump(60);
      expect(eventRefreshes, [null]);
    });

    test('an event with no line id triggers a full refresh', () async {
      coordinator = build()..start();
      sse.emitEvent(_event('a'));
      await _pump(60);
      expect(eventRefreshes, [null]);
    });

    test('reaching connected runs one immediate full refresh', () {
      coordinator = build()..start();
      coordinator.onSseConnectionStateChanged(SseConnectionState.connected);
      expect(eventRefreshes, [null]);
    });

    test('a non-connected transition does not refresh', () {
      coordinator = build()..start();
      coordinator.onSseConnectionStateChanged(SseConnectionState.reconnecting);
      expect(eventRefreshes, isEmpty);
    });

    test('resume restarts SSE and runs one immediate refresh', () {
      coordinator = build()..start();
      coordinator.pause();
      expect(sse.stopCount, 1);
      coordinator.resume();
      expect(sse.startCount, 2);
      expect(eventRefreshes, [null]);
    });

    test('the poll timer fires onPoll on the configured cadence', () async {
      coordinator = build(poll: const Duration(milliseconds: 30))..start();
      await _pump(80);
      expect(pollCalls, greaterThanOrEqualTo(1));
    });

    test('paused coordinator ignores events', () async {
      coordinator = build()..start();
      coordinator.pause();
      sse.emitEvent(_event('a', line: 1));
      await _pump(60);
      expect(eventRefreshes, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // SseClient (real client, fake Dio adapter)
  // ───────────────────────────────────────────────────────────────────────

  group('SseClient', () {
    late Dio dio;
    late _FakeSseAdapter adapter;
    late SseClient client;
    late List<SseConnectionState> states;
    late List<PalletizingAppSseEvent> events;

    setUp(() {
      dio = Dio();
      adapter = _FakeSseAdapter();
      dio.httpClientAdapter = adapter;
      client = SseClient(dio: dio, authStorage: _FakeAuthStorage());
      states = [];
      events = [];
      client.connectionState.listen(states.add);
      client.events.listen(events.add);
    });

    tearDown(() async {
      await client.dispose();
      for (final c in adapter.controllers) {
        if (!c.isClosed) await c.close();
      }
    });

    test('connects and reports the connected handshake', () async {
      client.start();
      await _pump();
      expect(adapter.fetchCount, 1);
      adapter.latest.add(
        _bytes('event: connected\ndata: {"status":"connected"}\n\n'),
      );
      await _pump();
      expect(states, contains(SseConnectionState.connected));
    });

    test('emits a parsed palletizing-lines-changed event', () async {
      client.start();
      await _pump();
      adapter.latest.add(
        _bytes('event: palletizing-lines-changed\n'
            'data: {"eventId":"e1","palletizingLineId":2,"reason":"PALLET_CREATED"}\n\n'),
      );
      await _pump();
      expect(events, hasLength(1));
      expect(events.single.eventId, 'e1');
      expect(events.single.palletizingLineId, 2);
    });

    test('drops a duplicate eventId', () async {
      client.start();
      await _pump();
      const frame = 'event: palletizing-lines-changed\n'
          'data: {"eventId":"dup","palletizingLineId":1}\n\n';
      adapter.latest.add(_bytes(frame));
      adapter.latest.add(_bytes(frame));
      await _pump();
      expect(events, hasLength(1));
    });

    test('ignores :ping keepalive comments', () async {
      client.start();
      await _pump();
      adapter.latest.add(_bytes(':ping\n'));
      await _pump();
      expect(events, isEmpty);
    });

    test('ignores a malformed event payload without crashing', () async {
      client.start();
      await _pump();
      adapter.latest.add(
        _bytes('event: palletizing-lines-changed\ndata: {bad json\n\n'),
      );
      // A good event right after still gets through — the stream survived.
      adapter.latest.add(
        _bytes('event: palletizing-lines-changed\n'
            'data: {"eventId":"ok"}\n\n'),
      );
      await _pump();
      expect(events, hasLength(1));
      expect(events.single.eventId, 'ok');
    });

    test('schedules a reconnect when the server closes the stream', () async {
      client.start();
      await _pump();
      await adapter.latest.close(); // server idle-close
      await _pump();
      expect(states, contains(SseConnectionState.reconnecting));
      client.stop(); // cancel the pending reconnect timer
    });

    test('declares the stream stale and reconnects after the stale timeout',
        () async {
      await client.dispose(); // drop the default 40s-timeout client
      client = SseClient(
        dio: dio,
        authStorage: _FakeAuthStorage(),
        staleTimeout: const Duration(milliseconds: 200),
      );
      client.connectionState.listen(states.add);
      client.start();
      await _pump();
      expect(adapter.fetchCount, 1);
      adapter.latest.add(_bytes('event: connected\ndata: {}\n\n'));
      await _pump();
      expect(states, contains(SseConnectionState.connected));

      // Silence — no frame, not even a :ping — past the 200ms stale window.
      // The watchdog must declare the socket dead and reconnect.
      await _pump(320);
      expect(states, contains(SseConnectionState.reconnecting));
      client.stop(); // cancel the pending reconnect timer
    });

    test('a heartbeat keeps the stale watchdog from firing', () async {
      await client.dispose();
      client = SseClient(
        dio: dio,
        authStorage: _FakeAuthStorage(),
        staleTimeout: const Duration(milliseconds: 240),
      );
      client.connectionState.listen(states.add);
      client.start();
      await _pump();
      adapter.latest.add(_bytes('event: connected\ndata: {}\n\n'));

      // A :ping inside each window keeps the stream alive well past one
      // stale timeout's worth of wall-clock silence.
      await _pump(160);
      adapter.latest.add(_bytes(':ping\n'));
      await _pump(160);
      adapter.latest.add(_bytes(':ping\n'));
      await _pump(160);

      expect(states, isNot(contains(SseConnectionState.reconnecting)));
      expect(adapter.fetchCount, 1); // no reconnect happened
      client.stop();
    });
  });
}
