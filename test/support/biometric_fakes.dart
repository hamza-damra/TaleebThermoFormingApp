// Shared fakes + fixtures for the biometric login gate tests.

import 'dart:async';

import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/domain/entities/biometric_login.dart';
import 'package:taleeb_thermoforming/domain/repositories/biometric_login_repository.dart';

const statusPath = '/api/v1/auth/biometric/login-attempts/status';

/// The verbatim server messages (handoff §10).
const requiredMessage = 'يرجى تمرير البصمة على جهاز البصمة ثم إعادة المحاولة.';
const expiredMessage =
    'انتهت صلاحية التحقق بالبصمة. يرجى تمرير البصمة مرة أخرى ثم إعادة المحاولة.';
const deviceMessage =
    'جهاز البصمة غير متصل حاليًا. يرجى المحاولة بعد قليل أو إبلاغ المسؤول.';
const mappingMissingMessage =
    'لم يتم ربط بصمتك بحسابك بعد. يرجى مراجعة مسؤول النظام.';

/// A recoverable refusal with an attempt to poll.
BiometricDenial denialWithToken(
  String token, {
  String code = BiometricCodes.verificationRequired,
  String message = requiredMessage,
}) => BiometricDenial(
  code: code,
  message: message,
  validitySeconds: 300,
  attemptAvailable: true,
  attemptToken: token,
  attemptExpiresAt: DateTime.utc(2026, 9, 24, 8, 15),
  statusPath: statusPath,
);

/// A refusal for which no attempt could be recorded (`attemptAvailable`
/// false) — or, with a `MAPPING_*` code, one only an admin can fix.
BiometricDenial denialWithoutToken({
  String code = BiometricCodes.verificationRequired,
  String message = requiredMessage,
}) => BiometricDenial(code: code, message: message, validitySeconds: 300);

/// Answers status calls from [answers], one per call: a
/// [BiometricAttemptStatus] or [BiometricAttemptStatusResponse] is returned,
/// anything else is thrown. With the queue empty a call is *held* like a real
/// long-poll: it answers only through [respond], or fails once its cancel
/// signal fires.
class FakeBiometricRepository implements BiometricLoginRepository {
  final List<Object> answers = [];

  /// The attempt token of every call, in order.
  final List<String> tokens = [];
  final List<String?> statusPaths = [];

  /// Held calls that were aborted through their cancel signal.
  int cancelledCalls = 0;

  Completer<BiometricAttemptStatusResponse>? _held;

  int get calls => tokens.length;

  bool get hasHeldCall => _held != null && !_held!.isCompleted;

  @override
  Future<BiometricAttemptStatusResponse> getBiometricAttemptStatus({
    required String? statusPath,
    required String attemptToken,
    Future<void>? cancelSignal,
  }) async {
    tokens.add(attemptToken);
    statusPaths.add(statusPath);
    if (answers.isNotEmpty) return _answer(answers.removeAt(0));

    final held = Completer<BiometricAttemptStatusResponse>();
    _held = held;
    cancelSignal?.then((_) {
      if (held.isCompleted) return;
      cancelledCalls++;
      held.completeError(ApiException.network());
    });
    return held.future;
  }

  /// Answers the held call.
  void respond(Object answer) {
    final held = _held!;
    _held = null;
    try {
      held.complete(_answer(answer));
    } catch (e) {
      held.completeError(e);
    }
  }

  static BiometricAttemptStatusResponse _answer(Object answer) {
    if (answer is BiometricAttemptStatus) {
      return BiometricAttemptStatusResponse(status: answer);
    }
    if (answer is BiometricAttemptStatusResponse) return answer;
    throw answer;
  }
}
