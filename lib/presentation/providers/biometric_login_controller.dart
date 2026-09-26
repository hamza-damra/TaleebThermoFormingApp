import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/biometric_login_strings.dart';
import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/biometric_login.dart';
import 'palletizing_provider.dart';

/// `BiometricLoginRepository.getBiometricAttemptStatus`.
typedef BiometricStatusFetcher =
    Future<BiometricAttemptStatusResponse> Function({
      required String? statusPath,
      required String attemptToken,
      Future<void>? cancelSignal,
    });

/// State of the fingerprint dialog (handoff §5).
enum BiometricLoginPhase {
  /// Polling; no valid fingerprint yet.
  waiting,

  /// Polling; the terminal reports offline.
  deviceOffline,

  /// The original login is being re-submitted.
  verifying,

  /// No attempt to poll (410, or a 403 without a token): scan, then retry.
  retry,

  /// The status call failed; polling again with backoff.
  network,

  /// `MAPPING_*` — only a SYSTEM_ADMIN can fix it.
  contactAdmin,

  /// The re-submitted login returned 2xx.
  success,

  /// The re-submitted login failed for a non-biometric reason (e.g. the PIN
  /// changed meanwhile). The PIN screen shows the error.
  failed,

  /// Closed by the user or because the login is no longer needed.
  cancelled;

  /// The dialog closes on these.
  bool get isTerminal => this == success || this == failed || this == cancelled;
}

/// Drives one biometric login attempt:
/// `waiting ⇄ deviceOffline → verifying → (success | new attempt | failed)`.
///
/// * Long-polls the status and issues the next poll as soon as one answers
///   `PENDING` / `DEVICE_UNAVAILABLE`.
/// * Network errors back off 1 s, 2 s, 4 s, 8 s, then 10 s, until the server
///   answers — its 410 is the only authority on expiry (the device clock may
///   be wrong).
/// * Re-submits the original login at most once per status answer (or per
///   tap on «إعادة المحاولة»). A new `BIOMETRIC_*` refusal replaces the
///   attempt.
/// * The attempt token stays in memory only and is dropped as soon as the
///   attempt ends, is replaced, is cancelled or the controller is disposed.
///   Nothing here logs.
class BiometricLoginController extends ChangeNotifier {
  final BiometricStatusFetcher _fetchStatus;
  final Future<PalletizerAuthOutcome> Function() _resubmit;
  final Duration Function(int consecutiveFailures) _backoff;

  BiometricLoginController({
    required BiometricDenial denial,
    required BiometricStatusFetcher fetchStatus,
    required Future<PalletizerAuthOutcome> Function() resubmit,
    Duration Function(int consecutiveFailures)? backoff,
  }) : _fetchStatus = fetchStatus,
       _resubmit = resubmit,
       _backoff = backoff ?? backoffDelay {
    _startAttempt(denial);
  }

  static const Duration maxBackoff = Duration(seconds: 10);

  /// Wait after the [consecutiveFailures]-th failed status call in a row.
  static Duration backoffDelay(int consecutiveFailures) {
    final n = consecutiveFailures < 1 ? 1 : consecutiveFailures;
    if (n > 4) return maxBackoff;
    final delay = Duration(seconds: 1 << (n - 1));
    return delay > maxBackoff ? maxBackoff : delay;
  }

  BiometricLoginPhase _phase = BiometricLoginPhase.waiting;

  /// `error.code` / `error.message` of the 403 that started the attempt.
  String _code = '';
  String _serverMessage = '';

  String? _token;
  String? _statusPath;
  String? _retryMessage;
  String? _adminMessage;
  ApiException? _failure;

  int _consecutiveFailures = 0;

  /// Bumped whenever polling stops; a loop whose generation is stale exits
  /// and its late answer is ignored.
  int _pollGen = 0;
  bool _polling = false;
  Completer<void>? _inFlightCancel;
  Completer<void>? _wake;
  Timer? _backoffTimer;

  bool _resubmitting = false;
  bool _closed = false;
  bool _disposed = false;

  BiometricLoginPhase get phase => _phase;

  /// `error.code` of the refusal behind the current attempt.
  String get denialCode => _code;

  /// Whether an attempt token is held (i.e. there is an attempt to poll).
  bool get hasAttemptToken => _token != null;

  bool get isPolling => _polling;

  bool get canCancel =>
      !_phase.isTerminal &&
      _phase != BiometricLoginPhase.verifying &&
      _phase != BiometricLoginPhase.contactAdmin;

  /// The server-worded text for the current state, or `null` when the dialog
  /// shows its own chrome string (§5: the server `message` is the body for
  /// every 403 code).
  String? get message {
    switch (_phase) {
      case BiometricLoginPhase.waiting:
        return _code == BiometricCodes.deviceUnavailable
            ? null
            : _serverMessage;
      case BiometricLoginPhase.deviceOffline:
        return _code == BiometricCodes.deviceUnavailable
            ? _serverMessage
            : null;
      case BiometricLoginPhase.retry:
        return _retryMessage;
      case BiometricLoginPhase.contactAdmin:
        return _adminMessage;
      case BiometricLoginPhase.failed:
        return _failure?.displayMessage;
      case BiometricLoginPhase.verifying:
      case BiometricLoginPhase.network:
      case BiometricLoginPhase.success:
      case BiometricLoginPhase.cancelled:
        return null;
    }
  }

  // ── User actions ──

  /// «إعادة المحاولة»: re-submits the original login once.
  Future<void> retry() async {
    if (_closed || _phase != BiometricLoginPhase.retry) return;
    await _resubmitOnce();
  }

  /// «إلغاء» / «حسنًا»: stops polling and discards the attempt.
  void cancel() {
    if (_closed || _phase == BiometricLoginPhase.verifying) return;
    _stopPolling();
    _discardAttempt();
    _setPhase(BiometricLoginPhase.cancelled);
    _closed = true;
  }

  /// App back in the foreground: poll now instead of waiting on a request or
  /// a backoff that went stale in the background.
  void onAppResumed() {
    if (_closed || !_polling) return;
    _stopPolling();
    _startPolling();
  }

  @override
  void dispose() {
    _closed = true;
    _disposed = true;
    _stopPolling();
    _discardAttempt();
    super.dispose();
  }

  // ── Attempt lifecycle ──

  void _startAttempt(BiometricDenial denial) {
    _stopPolling();
    _code = denial.code;
    _serverMessage = denial.message;
    _token = denial.canPoll ? denial.attemptToken : null;
    _statusPath = _token == null ? null : denial.statusPath;
    _consecutiveFailures = 0;
    _retryMessage = null;
    _adminMessage = null;
    _failure = null;

    if (denial.isMappingProblem) {
      _adminMessage = denial.message;
      _setPhase(BiometricLoginPhase.contactAdmin);
      return;
    }
    if (_token == null) {
      // Recoverable, but no attempt could be recorded: scan, then retry.
      _retryMessage = denial.message;
      _setPhase(BiometricLoginPhase.retry);
      return;
    }
    _setPhase(
      denial.isDeviceUnavailable
          ? BiometricLoginPhase.deviceOffline
          : BiometricLoginPhase.waiting,
    );
    _startPolling();
  }

  void _discardAttempt() {
    _token = null;
    _statusPath = null;
  }

  void _startPolling({Duration? after}) {
    if (_closed || _token == null) return;
    final gen = ++_pollGen;
    _polling = true;
    unawaited(_pollLoop(gen, after));
  }

  void _stopPolling() {
    _pollGen++;
    _polling = false;
    final inFlight = _inFlightCancel;
    _inFlightCancel = null;
    if (inFlight != null && !inFlight.isCompleted) inFlight.complete();
    _backoffTimer?.cancel();
    _backoffTimer = null;
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  bool _isCurrent(int gen) => !_closed && gen == _pollGen;

  Future<void> _pollLoop(int gen, Duration? initialDelay) async {
    if (initialDelay != null) await _sleep(initialDelay);
    while (_isCurrent(gen)) {
      final token = _token;
      if (token == null) return;
      final cancel = Completer<void>();
      _inFlightCancel = cancel;
      final BiometricAttemptStatusResponse response;
      try {
        response = await _fetchStatus(
          statusPath: _statusPath,
          attemptToken: token,
          cancelSignal: cancel.future,
        );
      } on BiometricAttemptExpiredException {
        if (!_isCurrent(gen)) return;
        _polling = false;
        _discardAttempt();
        _retryMessage = null;
        _setPhase(BiometricLoginPhase.retry);
        return;
      } catch (_) {
        if (!_isCurrent(gen)) return;
        _consecutiveFailures++;
        _setPhase(BiometricLoginPhase.network);
        await _sleep(_backoff(_consecutiveFailures));
        continue;
      } finally {
        if (identical(_inFlightCancel, cancel)) _inFlightCancel = null;
      }
      if (!_isCurrent(gen)) return;
      _consecutiveFailures = 0;

      final status = response.status;
      if (status.allowsResubmit) {
        await _resubmitOnce();
        return;
      }
      if (status.isMappingProblem) {
        _polling = false;
        _discardAttempt();
        _adminMessage = status == BiometricAttemptStatus.mappingMissing
            ? BiometricLoginStrings.serverMappingMissing
            : BiometricLoginStrings.serverMappingDisabled;
        _setPhase(BiometricLoginPhase.contactAdmin);
        return;
      }
      _setPhase(
        status == BiometricAttemptStatus.deviceUnavailable
            ? BiometricLoginPhase.deviceOffline
            : BiometricLoginPhase.waiting,
      );
    }
  }

  /// A backoff wait that [_stopPolling] can cut short.
  Future<void> _sleep(Duration delay) async {
    final wake = Completer<void>();
    _wake = wake;
    _backoffTimer = Timer(delay, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    if (identical(_wake, wake)) {
      _wake = null;
      _backoffTimer = null;
    }
  }

  Future<void> _resubmitOnce() async {
    if (_closed || _resubmitting) return;
    _stopPolling();
    _resubmitting = true;
    _setPhase(BiometricLoginPhase.verifying);

    PalletizerAuthOutcome outcome;
    try {
      outcome = await _resubmit();
    } catch (_) {
      outcome = const PalletizerAuthOutcome.failed();
    } finally {
      _resubmitting = false;
    }
    if (_closed) return;

    switch (outcome.status) {
      case PalletizerAuthStatus.success:
        _discardAttempt();
        _setPhase(BiometricLoginPhase.success);
        _closed = true;
      case PalletizerAuthStatus.biometricRequired:
        // Refused again (e.g. the fingerprint expired in between): a new
        // attempt with a new token.
        _startAttempt(outcome.denial!);
      case PalletizerAuthStatus.failed when outcome.isTransientFailure:
        if (_token != null) {
          // The attempt may still be good: poll again after a backoff and
          // re-submit on the next status answer.
          _consecutiveFailures++;
          _setPhase(BiometricLoginPhase.network);
          _startPolling(after: _backoff(_consecutiveFailures));
        } else {
          _retryMessage = outcome.error!.displayMessage;
          _setPhase(BiometricLoginPhase.retry);
        }
      case PalletizerAuthStatus.failed:
        _discardAttempt();
        _failure = outcome.error;
        _setPhase(BiometricLoginPhase.failed);
        _closed = true;
      case PalletizerAuthStatus.ignored:
        // Another login for the line is still in flight; let the user retry.
        _retryMessage = null;
        _setPhase(BiometricLoginPhase.retry);
    }
  }

  void _setPhase(BiometricLoginPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }
}
