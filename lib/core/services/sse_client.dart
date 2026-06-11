import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/datasources/auth_local_storage.dart';
import 'palletizing_event.dart';
import 'sse_frame_parser.dart';

/// Device-level Server-Sent Events client for the Palletizing App.
///
/// Opens a single long-lived stream to `GET /palletizing-line/app-events`
/// authenticated with `X-Device-Key` (no PIN, no session, no JWT). The stream
/// is a **refresh trigger only** — REST stays authoritative. The client:
///   * parses `connected` / `palletizing-lines-changed` frames, ignores `:ping`,
///   * de-duplicates events by `eventId`,
///   * tracks [SseConnectionState],
///   * auto-reconnects with exponential backoff after a drop or the server's
///     5-minute idle close,
///   * runs a stale-connection watchdog — if no frame arrives within
///     [_staleTimeout] (not even a `:ping` keepalive), the silently-dead
///     socket is aborted and reconnected.
class SseClient {
  SseClient({
    required Dio dio,
    required AuthLocalStorage authStorage,
    this.path = '/palletizing-line/app-events',
    Duration staleTimeout = const Duration(seconds: 40),
  })  : _dio = dio,
        _authStorage = authStorage,
        _staleTimeout = staleTimeout;

  final Dio _dio;
  final AuthLocalStorage _authStorage;

  /// Stream path. Contains `/palletizing-line/` so [Dio]'s existing interceptor
  /// attaches `X-Device-Key` automatically.
  final String path;

  /// Max silence — no frame at all, not even a `:ping` keepalive — tolerated
  /// before the stream is declared dead and force-reconnected. The backend
  /// sends a 25s heartbeat comment, so 40s comfortably covers one missed beat.
  /// See the SSE handoff §6 (stale connection). Injectable for tests.
  final Duration _staleTimeout;

  static const _eventConnected = 'connected';
  static const _eventLinesChanged = 'palletizing-lines-changed';
  static const _eventUrgentAnnouncement = 'urgent-manager-announcement';
  static const _maxDedupe = 50;
  static const _maxBackoffShift = 5; // 2^5 = 32s base, capped at 30s below

  final _stateController = StreamController<SseConnectionState>.broadcast();
  final _eventController = StreamController<PalletizingAppSseEvent>.broadcast();
  final _announcementController =
      StreamController<UrgentManagerAnnouncementEvent>.broadcast();
  final _parser = SseFrameParser();
  final Queue<String> _seenEventIds = Queue<String>();
  final Set<String> _seenEventIdSet = <String>{};
  final Random _random = Random();

  SseConnectionState _state = SseConnectionState.disconnected;
  bool _started = false;
  bool _connecting = false;
  int _retryAttempt = 0;
  CancelToken? _cancelToken;
  StreamSubscription<String>? _streamSub;
  Timer? _reconnectTimer;
  Timer? _staleTimer;

  /// Broadcasts connection-state transitions.
  Stream<SseConnectionState> get connectionState => _stateController.stream;

  /// Broadcasts de-duplicated `palletizing-lines-changed` events.
  Stream<PalletizingAppSseEvent> get events => _eventController.stream;

  /// Broadcasts `urgent-manager-announcement` nudges. Best-effort — the
  /// listener re-fetches the authoritative sanitized `pending` endpoint on each
  /// event. Carries no real message content.
  Stream<UrgentManagerAnnouncementEvent> get announcements =>
      _announcementController.stream;

  SseConnectionState get currentState => _state;

  /// Opens the stream. Idempotent — a second call while already running is a
  /// no-op, so a widget rebuild can never create a duplicate connection.
  void start() {
    if (_started) return;
    _started = true;
    _retryAttempt = 0;
    _connect();
  }

  /// Closes the stream and cancels any pending reconnect. Safe to call when
  /// already stopped.
  void stop() {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _connecting = false;
    _cancelToken?.cancel('SseClient.stop');
    _cancelToken = null;
    _streamSub?.cancel();
    _streamSub = null;
    _parser.reset();
    _setState(SseConnectionState.disconnected);
  }

  /// Permanently tears down the client. Call once at app shutdown.
  Future<void> dispose() async {
    stop();
    await _stateController.close();
    await _eventController.close();
    await _announcementController.close();
  }

  Future<void> _connect() async {
    if (!_started || _connecting) return;
    _connecting = true;
    _setState(_retryAttempt == 0
        ? SseConnectionState.connecting
        : SseConnectionState.reconnecting);

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final deviceKey = await _authStorage.getDeviceKey();
      final response = await _dio.get<ResponseBody>(
        path,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          // A long-lived stream must NOT inherit Dio's 30s receiveTimeout.
          receiveTimeout: Duration.zero,
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (deviceKey != null && deviceKey.isNotEmpty)
              'X-Device-Key': deviceKey,
          },
        ),
      );

      final body = response.data;
      if (body == null) {
        throw StateError('SSE response body was null');
      }

      _parser.reset();
      _streamSub = utf8.decoder.bind(body.stream).listen(
            _onChunk,
            onError: _onStreamError,
            onDone: _onStreamDone,
            cancelOnError: true,
          );
      // Arm the stale-connection watchdog: the first frame — the `connected`
      // handshake or a `:ping` — must arrive within [_staleTimeout].
      _resetStaleTimer();
      _connecting = false;
      _log('stream opened ($path)');
    } catch (e) {
      _connecting = false;
      if (!_started) return; // stopped while connecting — nothing to recover
      _log('connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onChunk(String chunk) {
    // Any bytes — even a partial line or a `:ping` — prove the socket is live.
    _resetStaleTimer();
    try {
      _handleFrames(_parser.addChunk(chunk));
    } catch (e) {
      // Defensive: a parser bug must never kill the stream.
      _log('chunk handling error: $e');
    }
  }

  void _handleFrames(List<SseFrame> frames) {
    for (final frame in frames) {
      // Any frame — even a `:ping` — proves the stream is healthy, so the
      // backoff resets.
      _retryAttempt = 0;

      if (frame.isComment) continue; // keepalive — ignore

      final event = frame.event;
      if (event == _eventConnected) {
        _setState(SseConnectionState.connected);
        _log('handshake received');
        continue;
      }
      if (event == _eventLinesChanged) {
        final parsed = PalletizingAppSseEvent.tryParse(frame.data);
        if (parsed == null) {
          _log('dropped malformed event payload');
          continue;
        }
        if (_isDuplicate(parsed.eventId)) {
          _log('dropped duplicate event ${parsed.eventId}');
          continue;
        }
        // A business frame also implies the stream is live, even if the named
        // `connected` handshake was missed.
        _setState(SseConnectionState.connected);
        _log('event received: $parsed');
        if (!_eventController.isClosed) _eventController.add(parsed);
        continue;
      }
      if (event == _eventUrgentAnnouncement) {
        // Best-effort nudge — no dedupe. The listener re-fetches the
        // authoritative `pending` endpoint, which is idempotent, so a repeated
        // nudge is harmless. A null parse still proves the stream is live.
        final parsed = UrgentManagerAnnouncementEvent.tryParse(frame.data);
        if (parsed == null) {
          _log('dropped malformed urgent-announcement payload');
          continue;
        }
        _setState(SseConnectionState.connected);
        _log('urgent announcement nudge received: $parsed');
        if (!_announcementController.isClosed) {
          _announcementController.add(parsed);
        }
        continue;
      }
      // Unknown event name — ignore.
    }
  }

  bool _isDuplicate(String eventId) {
    if (_seenEventIdSet.contains(eventId)) return true;
    _seenEventIdSet.add(eventId);
    _seenEventIds.addLast(eventId);
    if (_seenEventIds.length > _maxDedupe) {
      _seenEventIdSet.remove(_seenEventIds.removeFirst());
    }
    return false;
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _log('stream error: $error');
    _scheduleReconnect();
  }

  void _onStreamDone() {
    // A clean close is expected — the backend drops idle streams after 5 min.
    _log('stream closed by server');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started) return;
    _connecting = false;
    _staleTimer?.cancel();
    _staleTimer = null;
    _streamSub?.cancel();
    _streamSub = null;
    // Actively abort the request: a stale (silently-dead) socket would
    // otherwise linger until the OS TCP timeout. A no-op for a stream that has
    // already closed or errored.
    _cancelToken?.cancel('SseClient reconnect');
    _cancelToken = null;
    _parser.reset();

    // A reconnect is already pending — don't stack timers.
    if (_reconnectTimer?.isActive ?? false) return;

    _setState(SseConnectionState.reconnecting);
    final delay = _backoffDelay();
    _retryAttempt++;
    _log('reconnecting in ${delay.inMilliseconds}ms (attempt $_retryAttempt)');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  /// (Re)arms the stale-connection watchdog. Called when the stream opens and
  /// on every chunk, so any traffic — including a `:ping` keepalive — keeps it
  /// from firing.
  void _resetStaleTimer() {
    _staleTimer?.cancel();
    if (!_started) return;
    _staleTimer = Timer(_staleTimeout, _onStaleTimeout);
  }

  /// Fires when no frame has arrived for [_staleTimeout]. A heartbeat is due
  /// every 25s, so this means the socket is silently dead (no `onError` /
  /// `onDone` from the OS) — abort it and reconnect with the normal backoff.
  void _onStaleTimeout() {
    _staleTimer = null;
    if (!_started) return;
    _log('no frame for ${_staleTimeout.inSeconds}s — stale, forcing reconnect');
    _scheduleReconnect();
  }

  /// Exponential backoff (1, 2, 4, 8, 16, 30s cap) with up to 500ms jitter.
  Duration _backoffDelay() {
    final shift =
        _retryAttempt > _maxBackoffShift ? _maxBackoffShift : _retryAttempt;
    final seconds = min(1 << shift, 30);
    return Duration(milliseconds: seconds * 1000 + _random.nextInt(500));
  }

  void _setState(SseConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[SSE] $message');
  }
}
