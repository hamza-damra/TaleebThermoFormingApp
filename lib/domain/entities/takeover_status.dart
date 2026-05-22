/// Status of a Line Takeover Request, as reported by the backend (`V75`).
///
/// The Pallet Worker App is a **passive observer**: it never sends an
/// accept/reject; it only renders UI based on this status. `unknown` is the
/// safety fallback so a status added by a future backend never crashes the app.
enum TakeoverStatus {
  pending,
  accepted,
  rejected,
  completed,
  cancelled,
  timeoutAutoReleased,
  postAcceptTimeoutAutoReleased,
  unknown;

  /// Maps the backend status string. Anything unrecognised → [unknown].
  static TakeoverStatus fromString(String? raw) {
    switch (raw) {
      case 'PENDING':
        return TakeoverStatus.pending;
      case 'ACCEPTED':
        return TakeoverStatus.accepted;
      case 'REJECTED':
        return TakeoverStatus.rejected;
      case 'COMPLETED':
        return TakeoverStatus.completed;
      case 'CANCELLED':
        return TakeoverStatus.cancelled;
      case 'TIMEOUT_AUTO_RELEASED':
        return TakeoverStatus.timeoutAutoReleased;
      case 'POST_ACCEPT_TIMEOUT_AUTO_RELEASED':
        return TakeoverStatus.postAcceptTimeoutAutoReleased;
      default:
        return TakeoverStatus.unknown;
    }
  }

  /// A takeover request is still "live" — the worker should be reminded to
  /// fetch the operator. The line is usually still valid for production.
  bool get isActive =>
      this == TakeoverStatus.pending || this == TakeoverStatus.accepted;

  /// The takeover ended without releasing the line — resume normal work.
  bool get isCleared =>
      this == TakeoverStatus.rejected ||
      this == TakeoverStatus.completed ||
      this == TakeoverStatus.cancelled;

  /// The line was auto-released mid-handover — pallet creation must be blocked
  /// until the incoming operator claims the line and it is valid again.
  bool get isAutoReleased =>
      this == TakeoverStatus.timeoutAutoReleased ||
      this == TakeoverStatus.postAcceptTimeoutAutoReleased;
}
