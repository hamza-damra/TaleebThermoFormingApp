import '../entities/biometric_login.dart';

abstract class BiometricLoginRepository {
  /// GET `{statusPath}` — the long-poll on one login attempt. No
  /// `Authorization`, no device key: only `X-Biometric-Attempt-Token`.
  ///
  /// The server holds the request for up to 25 s. Throws
  /// [BiometricAttemptExpiredException] on 410 and an `ApiException` on any
  /// other failure. When [cancelSignal] completes the request is aborted and
  /// fails.
  Future<BiometricAttemptStatusResponse> getBiometricAttemptStatus({
    required String? statusPath,
    required String attemptToken,
    Future<void>? cancelSignal,
  });
}
