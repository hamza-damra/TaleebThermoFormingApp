import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/palletizing_event.dart';
import '../../domain/entities/manager_announcement.dart';
import '../../domain/repositories/palletizing_repository.dart';

/// Owns the **sanitized** urgent manager-announcement notice shown as a global
/// blocking overlay above `PalletizingScreen`.
///
/// Deliberately decoupled from `PalletizingProvider`:
///   * it reads the operating backend lineIds via [_lineIdsSupplier] (a
///     read-only snapshot) and never mutates line state;
///   * it subscribes to the existing device SSE stream's
///     `urgent-manager-announcement` nudges via the [announcements] stream
///     passed in, and to that same stream's connection-state transitions via
///     [connectionStates] — it never opens its own SSE connection.
///
/// Re-fetch triggers, per the handoff §Refresh expectations: app start, app
/// resume (both driven by `PalletizingScreen`), every SSE (re)connect, every
/// nudge, and the expiry deadline of the soonest timed notice.
///
/// The notice is THERMOFORMING domain-wide but the backend pending/ack
/// endpoints are keyed per lineId, so this notifier fetches across **all**
/// operating lines, merges by announcement id (one notice per unique id,
/// oldest-first), and on acknowledge acks every operating lineId (idempotent)
/// so the same notice never reappears when the operator switches machine tabs.
///
/// See [docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md].
class ManagerAnnouncementNotifier extends ChangeNotifier {
  ManagerAnnouncementNotifier(
    this._repository, {
    required List<int> Function() lineIdsSupplier,
    Stream<UrgentManagerAnnouncementEvent>? announcements,
    Stream<SseConnectionState>? connectionStates,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _lineIdsSupplier = lineIdsSupplier,
        _debounce = debounce {
    _announcementSub = announcements?.listen(_onSseNudge);
    _connectionSub = connectionStates?.listen(_onSseConnectionState);
  }

  final PalletizingRepository _repository;
  final List<int> Function() _lineIdsSupplier;
  final Duration _debounce;

  /// Slack added to the expiry deadline so the local clock is never *ahead* of
  /// the server's view when the re-fetch fires.
  static const Duration _expiryGrace = Duration(seconds: 1);

  StreamSubscription<UrgentManagerAnnouncementEvent>? _announcementSub;
  StreamSubscription<SseConnectionState>? _connectionSub;
  Timer? _debounceTimer;
  Timer? _expiryTimer;

  /// Arabic surface shown when an ack fails — the operator retries by tapping
  /// "فهمت" again.
  static const String ackErrorMessage =
      'تعذّر تأكيد الاستلام، يرجى المحاولة مرة أخرى.';

  // ── State ──
  final List<ManagerAnnouncement> _pending = [];
  bool _acking = false;
  String? _error;

  /// The notice to display, or `null` when there is nothing pending. Oldest
  /// first — one notice at a time.
  ManagerAnnouncement? get current => _pending.isEmpty ? null : _pending.first;

  /// Number of distinct pending notices (deduped across lines). Exposed for
  /// observability / tests.
  int get pendingCount => _pending.length;

  /// `true` while an ack round is in flight (disables the button + shows a
  /// spinner).
  bool get acking => _acking;

  /// Non-null when the last ack failed; the overlay shows it as retry text.
  String? get error => _error;

  /// Re-fetch trigger from the app: call after bootstrap loads lineIds and on
  /// app resume. A no-op (no error) when no lineIds are available yet.
  Future<void> refresh() => _fetchPending();

  /// Every nudge is handled identically, whatever its `action` — `CREATED`,
  /// `UPDATED`, `DEACTIVATED`, `DELETED`, an unknown future value, or none at
  /// all on an older backend. Re-fetching is always the safe response, so the
  /// event body is deliberately not inspected.
  void _onSseNudge(UrgentManagerAnnouncementEvent _) => _scheduleFetch();

  /// A (re)connect can follow a gap during which nudges were missed, so it must
  /// reconcile. Only the `connected` transition matters; `SseClient` emits it
  /// once per connection, not per frame.
  void _onSseConnectionState(SseConnectionState state) {
    if (state == SseConnectionState.connected) _scheduleFetch();
  }

  /// Coalesces trigger bursts (a reconnect immediately followed by the nudges
  /// it replays) into a single authoritative fetch.
  void _scheduleFetch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _fetchPending);
  }

  /// Fetches the sanitized pending notices for every operating lineId and
  /// rebuilds [_pending] as their union, deduped by id and ordered oldest-first.
  Future<void> _fetchPending() async {
    final lineIds = _lineIdsSupplier();
    if (lineIds.isEmpty) return; // bootstrap not ready — retry on resume / nudge

    var anySuccess = false;
    final results = await Future.wait(
      lineIds.map((lineId) async {
        try {
          final list = await _repository.getPendingUrgentAnnouncements(lineId);
          anySuccess = true;
          return list;
        } catch (_) {
          // Per-line failure is non-fatal; another line may still answer.
          return const <ManagerAnnouncement>[];
        }
      }),
    );

    // Total failure (every line errored): keep the prior state and try again on
    // the next nudge / resume, rather than hiding an unacked notice. Expired
    // notices are the one exception — they are dropped on the local clock so
    // the expiry guarantee survives an offline deadline.
    if (!anySuccess) {
      _dropExpiredLocally();
      return;
    }

    final byId = <int, ManagerAnnouncement>{};
    for (final list in results) {
      for (final a in list) {
        byId[a.id] = a;
      }
    }
    final merged = byId.values.toList()..sort(_oldestFirst);

    _pending
      ..clear()
      ..addAll(merged);
    _armExpiryTimer();
    notifyListeners();
  }

  /// Arms a one-shot timer on the soonest **strictly future** `expiresAt` in
  /// [_pending], so a timed notice clears on the second instead of at the next
  /// natural re-fetch.
  ///
  /// Deadlines already in the past are skipped on purpose: the backend filters
  /// expired rows itself, so a row that is still pending while the local clock
  /// says otherwise means the device clock runs ahead — and re-arming at zero
  /// would spin fetch → fire → fetch forever.
  void _armExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;

    final now = DateTime.now();
    Duration? soonest;
    for (final a in _pending) {
      final expiresAt = a.expiresAt;
      if (expiresAt == null) continue;
      final remaining = expiresAt.difference(now);
      if (remaining <= Duration.zero) continue;
      if (soonest == null || remaining < soonest) soonest = remaining;
    }
    if (soonest == null) return;

    _expiryTimer = Timer(soonest + _expiryGrace, _onExpiryDeadline);
  }

  /// The soonest notice has just expired. REST stays authoritative: re-fetch
  /// and let the server's (expiry-filtered) answer decide, so a skewed device
  /// clock can never hide a notice the backend still considers live. When every
  /// line is unreachable, [_fetchPending] falls back to [_dropExpiredLocally].
  void _onExpiryDeadline() {
    _expiryTimer = null;
    _fetchPending();
  }

  /// Offline fallback for the expiry guarantee: drop notices whose deadline has
  /// passed per the local clock, leaving every other pending notice untouched.
  void _dropExpiredLocally() {
    final now = DateTime.now();
    final before = _pending.length;
    _pending.removeWhere((a) => a.isExpiredAt(now));
    _armExpiryTimer();
    if (_pending.length != before) notifyListeners();
  }

  /// Acknowledges the current notice for **all** operating lineIds (idempotent).
  /// Closes the notice only when every ack succeeds; on any failure the modal
  /// stays open with [error] set so the operator can retry.
  Future<void> acknowledgeCurrent() async {
    final announcement = current;
    if (announcement == null || _acking) return;

    _acking = true;
    _error = null;
    notifyListeners();

    final lineIds = _lineIdsSupplier();
    if (lineIds.isEmpty) {
      _acking = false;
      _error = ackErrorMessage;
      notifyListeners();
      return;
    }

    var failed = false;
    await Future.wait(
      lineIds.map((lineId) async {
        try {
          await _repository.ackUrgentAnnouncement(
            announcementId: announcement.id,
            lineId: lineId,
          );
        } catch (_) {
          failed = true;
        }
      }),
    );

    if (failed) {
      _error = ackErrorMessage;
    } else {
      _pending.removeWhere((a) => a.id == announcement.id);
      // The acked notice may have owned the armed deadline.
      _armExpiryTimer();
      _error = null;
    }
    _acking = false;
    notifyListeners();
  }

  static int _oldestFirst(ManagerAnnouncement a, ManagerAnnouncement b) {
    final ad = a.createdAt;
    final bd = b.createdAt;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad == null && bd != null) {
      return 1; // unknown timestamps sort last
    } else if (ad != null && bd == null) {
      return -1;
    }
    return a.id.compareTo(b.id);
  }

  @override
  void dispose() {
    _announcementSub?.cancel();
    _connectionSub?.cancel();
    _debounceTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}
