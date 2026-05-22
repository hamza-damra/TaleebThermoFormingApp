import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Lifecycle of the device-level SSE connection.
enum SseConnectionState {
  /// Opening the stream for the first time.
  connecting,

  /// Stream is open and the `connected` handshake (or a business frame) was
  /// received.
  connected,

  /// Stream dropped; a reconnect is scheduled / in progress.
  reconnecting,

  /// Stream is intentionally closed (app paused, screen disposed).
  disconnected,
}

/// A parsed `palletizing-lines-changed` SSE event.
///
/// The payload is a **refresh trigger only** — it deliberately carries no
/// business state. The app keeps just [eventId] (dedupe) and [reason] /
/// [version] (debug logging); after any event it refetches authoritative REST.
@immutable
class PalletizingAppSseEvent {
  /// Server-assigned UUID. Used for client-side dedupe.
  final String eventId;

  /// Coarse discriminator — always `LINE_STATE_CHANGED` today.
  final String? type;

  /// Specific change reason (hint only — every event maps to a refresh).
  final String? reason;

  /// The palletizing line whose state changed. Used to target the refresh.
  final int? palletizingLineId;

  /// Process-local monotonic counter — ordering hint for logs, not authority.
  final int? version;

  /// Present only on `LINE_TAKEOVER_*` frames.
  final int? thermoformingLineId;

  /// ISO-8601 timestamp from the backend, when parseable.
  final DateTime? occurredAt;

  const PalletizingAppSseEvent({
    required this.eventId,
    this.type,
    this.reason,
    this.palletizingLineId,
    this.version,
    this.thermoformingLineId,
    this.occurredAt,
  });

  /// Parses an SSE `data:` payload. Returns `null` — never throws — on
  /// malformed JSON, a non-object body, or a missing/empty `eventId`, so a
  /// corrupt frame can be dropped without crashing the stream.
  static PalletizingAppSseEvent? tryParse(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return null;
      final eventId = decoded['eventId'];
      if (eventId is! String || eventId.isEmpty) return null;
      return PalletizingAppSseEvent(
        eventId: eventId,
        type: _asString(decoded['type']),
        reason: _asString(decoded['reason']),
        palletizingLineId: _asInt(decoded['palletizingLineId']),
        version: _asInt(decoded['version']),
        thermoformingLineId: _asInt(decoded['thermoformingLineId']),
        occurredAt: _asDate(decoded['occurredAt']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _asString(Object? v) => v is String ? v : null;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDate(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  @override
  String toString() =>
      'PalletizingAppSseEvent(reason: $reason, line: $palletizingLineId, '
      'id: $eventId, version: $version)';
}
