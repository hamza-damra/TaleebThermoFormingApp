import 'dart:async';

import 'package:flutter/foundation.dart';

import 'palletizing_event.dart';
import 'sse_client.dart';

/// Owns the single REST refresh timer and bridges SSE events into refreshes.
///
/// There is exactly one of these, owned by `PalletizingProvider`. It replaces
/// the old screen-driven poll timer so the refresh cadence can react to SSE
/// connection state the instant it changes — a long safety interval can never
/// strand a disconnect.
///
/// Responsibilities:
///   * one self-rescheduling poll timer (interval from [nextInterval]),
///   * debounce SSE event bursts (250ms) into a single batch handed to
///     [onEvents] — the provider decides between a bootstrap re-fetch and a
///     per-line `/state` refresh, because only it knows the rendered lines,
///   * an immediate full refresh ([onFullRefresh], a silent bootstrap) on
///     (re)connect and on app resume — frames may have been missed.
///
/// The provider owns the SSE connection-state subscription and forwards
/// transitions via [onSseConnectionStateChanged] — this guarantees the
/// provider's cadence inputs are updated before the timer is rescheduled.
class RefreshCoordinator {
  RefreshCoordinator({
    required SseClient sseClient,
    required Future<void> Function() onPoll,
    required Future<void> Function(List<PalletizingAppSseEvent> events)
    onEvents,
    required Future<void> Function() onFullRefresh,
    required Duration Function() nextInterval,
    Duration debounce = const Duration(milliseconds: 250),
  }) : _sse = sseClient,
       _onPoll = onPoll,
       _onEvents = onEvents,
       _onFullRefresh = onFullRefresh,
       _nextInterval = nextInterval,
       _debounce = debounce;

  final SseClient _sse;
  final Future<void> Function() _onPoll;
  final Future<void> Function(List<PalletizingAppSseEvent> events) _onEvents;
  final Future<void> Function() _onFullRefresh;
  final Duration Function() _nextInterval;

  /// SSE-event debounce window — bursts within it collapse into one refresh.
  final Duration _debounce;

  Timer? _pollTimer;
  Timer? _debounceTimer;
  StreamSubscription<PalletizingAppSseEvent>? _eventSub;

  bool _running = false;
  bool _polling = false;

  // Debounce accumulator — every frame received inside one window, in order.
  final List<PalletizingAppSseEvent> _pendingEvents = [];

  /// `true` while the loop is active (started and not paused/stopped).
  bool get isRunning => _running;

  /// Starts the SSE stream and the poll loop. Idempotent.
  void start() {
    if (_running) return;
    _running = true;
    _eventSub ??= _sse.events.listen(_onEvent);
    _sse.start();
    _scheduleNextPoll();
  }

  /// Pauses while the app is backgrounded: cancels timers and closes the SSE
  /// stream (the OS would kill the socket anyway). Keeps the event
  /// subscription so [resume] does not need to re-wire it.
  void pause() {
    if (!_running) return;
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingEvents.clear();
    _sse.stop();
  }

  /// Resumes after the app returns to the foreground: restarts the SSE stream,
  /// runs one immediate refresh (a transition may have committed while
  /// backgrounded), and reschedules the poll loop.
  void resume() {
    if (_running) return;
    _running = true;
    _sse.start();
    _scheduleNextPoll();
    _onFullRefresh();
  }

  /// Permanently stops the loop. Call from the provider's `dispose`.
  void stop() {
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingEvents.clear();
    _eventSub?.cancel();
    _eventSub = null;
    _sse.stop();
  }

  /// Stops the loop and disposes the owned SSE client.
  Future<void> dispose() async {
    stop();
    await _sse.dispose();
  }

  /// Forwarded by the provider on every SSE connection-state transition. On
  /// reaching [SseConnectionState.connected] it runs one immediate full
  /// refresh to reconcile any gap (the broker is in-memory, so frames sent
  /// while disconnected are lost); on every transition it reschedules the poll timer so
  /// the cadence (which depends on connection state) takes effect at once.
  void onSseConnectionStateChanged(SseConnectionState state) {
    if (!_running) return;
    if (state == SseConnectionState.connected) {
      _onFullRefresh();
    }
    _scheduleNextPoll();
  }

  /// Runs an immediate one-shot refresh — used for manual pull-to-refresh.
  void triggerImmediateRefresh() {
    if (!_running) return;
    _onFullRefresh();
  }

  void _onEvent(PalletizingAppSseEvent event) {
    if (!_running) return;
    _pendingEvents.add(event);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _flushDebounced);
  }

  void _flushDebounced() {
    _debounceTimer = null;
    final batch = List<PalletizingAppSseEvent>.unmodifiable(_pendingEvents);
    _pendingEvents.clear();
    if (!_running || batch.isEmpty) return;
    _onEvents(batch);
  }

  void _scheduleNextPoll() {
    if (!_running) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(_nextInterval(), _runPoll);
  }

  Future<void> _runPoll() async {
    if (!_running) return;
    if (_polling) {
      _scheduleNextPoll();
      return;
    }
    _polling = true;
    try {
      await _onPoll();
    } catch (e) {
      if (kDebugMode) debugPrint('[RefreshCoordinator] poll error: $e');
    } finally {
      _polling = false;
      _scheduleNextPoll();
    }
  }
}
