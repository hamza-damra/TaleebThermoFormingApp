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
///     passed in — it never opens its own SSE connection.
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
    Duration debounce = const Duration(milliseconds: 300),
  })  : _lineIdsSupplier = lineIdsSupplier,
        _debounce = debounce {
    _announcementSub = announcements?.listen(_onSseNudge);
  }

  final PalletizingRepository _repository;
  final List<int> Function() _lineIdsSupplier;
  final Duration _debounce;

  StreamSubscription<UrgentManagerAnnouncementEvent>? _announcementSub;
  Timer? _debounceTimer;

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

  void _onSseNudge(UrgentManagerAnnouncementEvent _) {
    // Coalesce nudge bursts into a single authoritative fetch.
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
    // the next nudge / resume, rather than hiding an unacked notice.
    if (!anySuccess) return;

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
    notifyListeners();
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
    _debounceTimer?.cancel();
    super.dispose();
  }
}
