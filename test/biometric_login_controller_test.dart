// Biometric login gate — the one-attempt controller behind the fingerprint
// dialog (handoff §5, §8, §12).
//   * every status value and both 403 variants map to the right state;
//   * the original login is re-submitted exactly once per status answer;
//   * a re-submit refused again switches to the new attempt, without a loop;
//   * 410 → Retry, and «إعادة المحاولة» re-submits;
//   * network errors back off (1, 2, 4, 8, then 10 s) and recover;
//   * cancel / dispose stop polling and drop the token; resume polls now.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants/biometric_login_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/domain/entities/biometric_login.dart';
import 'package:taleeb_thermoforming/presentation/providers/biometric_login_controller.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';

import 'support/biometric_fakes.dart';

class _Harness {
  final repo = FakeBiometricRepository();

  /// Consumed one per re-submit; empty → success.
  final List<PalletizerAuthOutcome> resubmitResults = [];

  /// When set, every re-submit waits for it.
  Completer<PalletizerAuthOutcome>? resubmitGate;
  int resubmits = 0;

  /// The real schedule the controller asked for — the wait itself is zero.
  final List<Duration> backoffs = [];
  Duration Function(int)? backoffOverride;

  late final BiometricLoginController controller;
  bool _disposed = false;

  BiometricLoginController start(BiometricDenial denial) {
    controller = BiometricLoginController(
      denial: denial,
      fetchStatus: repo.getBiometricAttemptStatus,
      resubmit: () async {
        resubmits++;
        final gate = resubmitGate;
        if (gate != null) return gate.future;
        return resubmitResults.isEmpty
            ? const PalletizerAuthOutcome.success()
            : resubmitResults.removeAt(0);
      },
      backoff: (n) {
        backoffs.add(BiometricLoginController.backoffDelay(n));
        return backoffOverride?.call(n) ?? Duration.zero;
      },
    );
    addTearDown(dispose);
    return controller;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
  }
}

const _verified = BiometricAttemptStatus.verified;
const _pending = BiometricAttemptStatus.pending;

void main() {
  group('opening state from the refusal', () {
    test('403 with a token → Waiting, polling with that token', () async {
      final h = _Harness();
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.waiting);
      expect(c.message, requiredMessage, reason: 'server message verbatim');
      expect(c.isPolling, isTrue);
      expect(c.canCancel, isTrue);
      expect(h.repo.tokens, ['tok-1']);
      expect(h.repo.statusPaths, [statusPath]);
      expect(h.repo.hasHeldCall, isTrue);
    });

    test('DEVICE_UNAVAILABLE → Device offline, still polling', () async {
      final h = _Harness();
      final c = h.start(
        denialWithToken(
          'tok-1',
          code: BiometricCodes.deviceUnavailable,
          message: deviceMessage,
        ),
      );
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.deviceOffline);
      expect(c.message, deviceMessage);
      expect(h.repo.calls, 1);
    });

    test('403 without a token → Retry with the server message, no '
        'polling', () async {
      final h = _Harness();
      final c = h.start(denialWithoutToken());
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.retry);
      expect(c.message, requiredMessage);
      expect(c.hasAttemptToken, isFalse);
      expect(h.repo.calls, 0);
      expect(h.resubmits, 0, reason: 'never re-submitted automatically');
    });

    test('MAPPING_* → Contact admin; no polling, no retry', () async {
      final h = _Harness();
      final c = h.start(
        denialWithoutToken(
          code: BiometricCodes.mappingMissing,
          message: mappingMissingMessage,
        ),
      );
      await c.retry();
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.contactAdmin);
      expect(c.message, mappingMissingMessage);
      expect(c.canCancel, isFalse, reason: 'only «حسنًا» is offered');
      expect(h.repo.calls, 0);
      expect(h.resubmits, 0);

      c.cancel();
      expect(c.phase, BiometricLoginPhase.cancelled);
    });

    test('a MAPPING_* code never polls even if a token were sent', () async {
      final h = _Harness();
      final c = h.start(
        denialWithToken(
          'tok-1',
          code: BiometricCodes.mappingDisabled,
          message: 'x',
        ),
      );
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.contactAdmin);
      expect(h.repo.calls, 0);
    });
  });

  group('status answers', () {
    test('PENDING polls again at once; DEVICE_UNAVAILABLE switches to Device '
        'offline and keeps polling', () async {
      final h = _Harness();
      h.repo.answers.addAll([
        _pending,
        _pending,
        BiometricAttemptStatus.deviceUnavailable,
      ]);
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(h.repo.calls, 4, reason: '3 answered + the held long-poll');
      expect(c.phase, BiometricLoginPhase.deviceOffline);
      expect(c.message, isNull, reason: 'the dialog shows its own text');

      h.repo.respond(_pending);
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.waiting);
      expect(h.repo.calls, 5);
      expect(h.resubmits, 0);
    });

    test('an unknown status value is treated as PENDING', () async {
      final h = _Harness();
      h.repo.answers.add(
        BiometricAttemptStatusResponse(
          status: BiometricAttemptStatus.fromWire('SOMETHING_NEW'),
        ),
      );
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.waiting);
      expect(h.repo.calls, 2);
      expect(h.resubmits, 0);
    });

    for (final status in [
      BiometricAttemptStatus.verified,
      BiometricAttemptStatus.enforcementSuspended,
      BiometricAttemptStatus.notRequired,
    ]) {
      test('${status.name} → exactly one re-submit, then success', () async {
        final h = _Harness();
        h.repo.answers.add(status);
        final c = h.start(denialWithToken('tok-1'));
        await pumpEventQueue();

        expect(h.resubmits, 1);
        expect(c.phase, BiometricLoginPhase.success);
        expect(c.hasAttemptToken, isFalse);
        expect(h.repo.calls, 1, reason: 'no poll after the status answer');
      });
    }

    test('Verifying is shown while the re-submit is in flight', () async {
      final h = _Harness()..resubmitGate = Completer();
      h.repo.answers.add(_verified);
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.verifying);
      expect(c.canCancel, isFalse, reason: 'no buttons while verifying');
      c.cancel();
      expect(c.phase, BiometricLoginPhase.verifying);

      h.resubmitGate!.complete(const PalletizerAuthOutcome.success());
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.success);
      expect(h.resubmits, 1);
    });

    test('MAPPING_* while waiting → Contact admin with the verbatim server '
        'text; polling stops', () async {
      for (final (status, text) in [
        (
          BiometricAttemptStatus.mappingMissing,
          BiometricLoginStrings.serverMappingMissing,
        ),
        (
          BiometricAttemptStatus.mappingDisabled,
          BiometricLoginStrings.serverMappingDisabled,
        ),
      ]) {
        final h = _Harness();
        h.repo.answers.add(status);
        final c = h.start(denialWithToken('tok-1'));
        await pumpEventQueue();

        expect(c.phase, BiometricLoginPhase.contactAdmin);
        expect(c.message, text);
        expect(c.hasAttemptToken, isFalse);
        expect(h.repo.calls, 1);
        expect(h.resubmits, 0);
      }
    });

    test('410 → Retry; «إعادة المحاولة» re-submits the original login '
        'once', () async {
      final h = _Harness();
      h.repo.answers.add(BiometricAttemptExpiredException());
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.retry);
      expect(c.message, isNull, reason: 'the dialog shows its retry text');
      expect(c.hasAttemptToken, isFalse);
      expect(c.isPolling, isFalse);
      expect(h.repo.calls, 1);
      expect(h.resubmits, 0);

      await c.retry();
      expect(h.resubmits, 1);
      expect(c.phase, BiometricLoginPhase.success);
    });
  });

  group('re-submit results', () {
    test('refused again → the new attempt (new token), no loop', () async {
      final h = _Harness();
      h.repo.answers.add(_verified);
      h.resubmitResults.add(
        PalletizerAuthOutcome.biometricRequired(
          denialWithToken(
            'tok-2',
            code: BiometricCodes.verificationExpired,
            message: expiredMessage,
          ),
        ),
      );
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(h.resubmits, 1);
      expect(c.phase, BiometricLoginPhase.waiting);
      expect(c.denialCode, BiometricCodes.verificationExpired);
      expect(c.message, expiredMessage);
      expect(h.repo.tokens, ['tok-1', 'tok-2']);

      // Only a new status answer can lead to another re-submit.
      await pumpEventQueue();
      expect(h.resubmits, 1);
      h.repo.respond(_verified);
      await pumpEventQueue();
      expect(h.resubmits, 2);
      expect(c.phase, BiometricLoginPhase.success);
    });

    test('refused again without a token → Retry', () async {
      final h = _Harness();
      h.repo.answers.add(_verified);
      h.resubmitResults.add(
        PalletizerAuthOutcome.biometricRequired(denialWithoutToken()),
      );
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.retry);
      expect(c.message, requiredMessage);
      expect(h.repo.calls, 1);
    });

    test('a credential error (PIN changed meanwhile) → failed with that '
        'error', () async {
      final h = _Harness();
      h.repo.answers.add(_verified);
      h.resubmitResults.add(
        PalletizerAuthOutcome.failed(
          ApiException(
            code: 'OPERATOR_PIN_INVALID',
            message: 'x',
            statusCode: 401,
          ),
        ),
      );
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.failed);
      expect(c.message, 'رمز المشغل غير صحيح');
      expect(c.hasAttemptToken, isFalse);
      expect(h.repo.calls, 1);
    });

    test('a re-submit lost to the network polls again after a backoff; one '
        're-submit per status answer', () async {
      final h = _Harness();
      h.repo.answers.addAll([_verified, _verified]);
      h.resubmitResults.addAll([
        PalletizerAuthOutcome.failed(ApiException.network()),
        const PalletizerAuthOutcome.success(),
      ]);
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(h.resubmits, 2);
      expect(h.repo.calls, 2);
      expect(h.backoffs, [const Duration(seconds: 1)]);
      expect(c.phase, BiometricLoginPhase.success);
    });

    test('taps on «إعادة المحاولة» during a re-submit are ignored', () async {
      final h = _Harness()..resubmitGate = Completer();
      final c = h.start(denialWithoutToken());

      unawaited(c.retry());
      unawaited(c.retry());
      await pumpEventQueue();
      expect(h.resubmits, 1);
      expect(c.phase, BiometricLoginPhase.verifying);

      h.resubmitGate!.complete(const PalletizerAuthOutcome.success());
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.success);
      expect(h.resubmits, 1);
    });
  });

  group('network', () {
    test('backoff schedule: 1 s, 2 s, 4 s, 8 s, then at most 10 s', () {
      expect(
        [for (var n = 1; n <= 7; n++) BiometricLoginController.backoffDelay(n)],
        const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 10),
          Duration(seconds: 10),
          Duration(seconds: 10),
        ],
      );
    });

    test('status failures show Network, back off and recover on the next '
        'answer', () async {
      final h = _Harness();
      h.repo.answers.addAll([
        for (var i = 0; i < 6; i++) ApiException.network(),
      ]);
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.network);
      expect(c.isPolling, isTrue);
      expect(h.backoffs, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 10),
        Duration(seconds: 10),
      ]);
      expect(h.repo.calls, 7, reason: '6 failures + the held long-poll');
      expect(h.repo.tokens.toSet(), {'tok-1'});

      h.repo.respond(_pending);
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.waiting);

      // A success resets the schedule.
      h.repo.respond(ApiException.timeout());
      await pumpEventQueue();
      expect(h.backoffs.last, const Duration(seconds: 1));
    });
  });

  group('lifecycle', () {
    test('cancel stops polling and discards the token', () async {
      final h = _Harness();
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();
      expect(h.repo.hasHeldCall, isTrue);

      c.cancel();
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.cancelled);
      expect(c.hasAttemptToken, isFalse);
      expect(c.isPolling, isFalse);
      expect(h.repo.cancelledCalls, 1, reason: 'the long-poll is aborted');
      await pumpEventQueue();
      expect(h.repo.calls, 1);
      expect(h.resubmits, 0);
    });

    test('dispose aborts the long-poll and drops the token', () async {
      final h = _Harness();
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      h.dispose();
      await pumpEventQueue();

      expect(h.repo.cancelledCalls, 1);
      expect(c.hasAttemptToken, isFalse);
      expect(h.repo.calls, 1);
    });

    test('a late VERIFIED after cancel is ignored', () async {
      // A server that answers even though the request was cancelled.
      final late = Completer<BiometricAttemptStatusResponse>();
      var resubmits = 0;
      final c = BiometricLoginController(
        denial: denialWithToken('tok-1'),
        fetchStatus:
            ({
              required String? statusPath,
              required String attemptToken,
              Future<void>? cancelSignal,
            }) => late.future,
        resubmit: () async {
          resubmits++;
          return const PalletizerAuthOutcome.success();
        },
      );
      addTearDown(c.dispose);
      await pumpEventQueue();

      c.cancel();
      late.complete(const BiometricAttemptStatusResponse(status: _verified));
      await pumpEventQueue();

      expect(c.phase, BiometricLoginPhase.cancelled);
      expect(resubmits, 0);
    });

    test('on app resume a stale long-poll is replaced by a new one '
        'now', () async {
      final h = _Harness();
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();

      c.onAppResumed();
      await pumpEventQueue();

      expect(h.repo.cancelledCalls, 1);
      expect(h.repo.calls, 2);
      expect(c.isPolling, isTrue);
      expect(c.phase, BiometricLoginPhase.waiting);
    });

    test('on app resume a pending backoff is skipped', () async {
      final h = _Harness()..backoffOverride = (_) => const Duration(hours: 1);
      h.repo.answers.add(ApiException.network());
      final c = h.start(denialWithToken('tok-1'));
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.network);
      expect(h.repo.calls, 1);

      c.onAppResumed();
      await pumpEventQueue();
      expect(h.repo.calls, 2);

      // An expired attempt found on return → Retry.
      h.repo.respond(BiometricAttemptExpiredException());
      await pumpEventQueue();
      expect(c.phase, BiometricLoginPhase.retry);
    });

    test('resume does nothing when not polling', () async {
      final h = _Harness();
      final c = h.start(denialWithoutToken());
      c.onAppResumed();
      await pumpEventQueue();
      expect(h.repo.calls, 0);
      expect(c.phase, BiometricLoginPhase.retry);
    });
  });

  test('the attempt token never reaches the log sink', () async {
    const secret = 'SECRET-ATTEMPT-TOKEN-7f3a';
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);

    final h = _Harness();
    h.repo.answers.addAll([
      _pending,
      ApiException.network(),
      BiometricAttemptStatus.deviceUnavailable,
      _verified,
    ]);
    h.resubmitResults.add(
      PalletizerAuthOutcome.biometricRequired(denialWithToken(secret)),
    );
    final c = h.start(denialWithToken(secret));
    await pumpEventQueue();
    c.cancel();
    debugPrint('controller: $c phase=${c.phase} message=${c.message}');

    expect(logs.where((l) => l.contains(secret)), isEmpty);
  });
}
