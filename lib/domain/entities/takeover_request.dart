import 'takeover_status.dart';

/// A pending/active Line Takeover Request bound to a production line.
///
/// Mirrors the backend `pendingTakeoverRequest` object on the line-state /
/// bootstrap response. Countdowns are **backend-authoritative**: prefer the
/// absolute deadline ([expiresAt] / [handoverExpiresAt]) and fall back to the
/// backend-computed `*RemainingSeconds` only when no deadline is supplied.
class TakeoverRequest {
  /// Stable per-request identifier. Used to de-duplicate the sound / vibration
  /// / dialog so they fire exactly once per request. Parsed defensively as a
  /// string regardless of the backend's JSON type.
  final String id;
  final TakeoverStatus status;
  final String? statusDisplayNameAr;
  final String? requestedByOperatorName;
  final String? currentOperatorName;
  final DateTime? requestedAt;

  /// Deadline of the 10-minute PENDING window.
  final DateTime? expiresAt;

  /// Backend-computed fallback for the PENDING window.
  final int? remainingSeconds;

  /// Deadline of the 5-minute post-ACCEPT handover window.
  final DateTime? handoverExpiresAt;

  /// Backend-computed fallback for the post-ACCEPT window.
  final int? handoverRemainingSeconds;

  final bool autoRelease;

  const TakeoverRequest({
    required this.id,
    required this.status,
    this.statusDisplayNameAr,
    this.requestedByOperatorName,
    this.currentOperatorName,
    this.requestedAt,
    this.expiresAt,
    this.remainingSeconds,
    this.handoverExpiresAt,
    this.handoverRemainingSeconds,
    this.autoRelease = false,
  });

  /// Remaining time on the PENDING window. Prefers the absolute [expiresAt]
  /// (drift-free, survives app resume); falls back to [remainingSeconds].
  /// Returns `null` when neither is known. Never negative.
  Duration? pendingRemaining() => _remaining(expiresAt, remainingSeconds);

  /// Remaining time on the post-ACCEPT handover window.
  Duration? handoverRemaining() =>
      _remaining(handoverExpiresAt, handoverRemainingSeconds);

  static Duration? _remaining(DateTime? deadline, int? fallbackSeconds) {
    if (deadline != null) {
      final diff = deadline.difference(DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    }
    if (fallbackSeconds != null) {
      return Duration(seconds: fallbackSeconds < 0 ? 0 : fallbackSeconds);
    }
    return null;
  }
}
