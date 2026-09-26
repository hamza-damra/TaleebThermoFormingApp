/// Biometric login gate — a fingerprint check before a new palletizer login.
/// See docs/FRONTEND_HANDOFF_PALLETIZING_APP_BIOMETRIC_LOGIN_GATE.md.
///
/// The attempt token is a secret: it lives in memory for the life of the
/// fingerprint dialog only. It is never logged, persisted, displayed or put
/// in a URL — no `toString` here includes it.
library;

import '../../core/constants/biometric_login_strings.dart';
import '../../core/exceptions/api_exception.dart';

/// `error.code` values of the gate (§4.4). Branch on these, never on the HTTP
/// status alone — other 403s keep their current handling.
abstract final class BiometricCodes {
  static const String prefix = 'BIOMETRIC_';
  static const String verificationRequired = 'BIOMETRIC_VERIFICATION_REQUIRED';
  static const String verificationExpired = 'BIOMETRIC_VERIFICATION_EXPIRED';
  static const String deviceUnavailable = 'BIOMETRIC_DEVICE_UNAVAILABLE';
  static const String mappingMissing = 'BIOMETRIC_MAPPING_MISSING';
  static const String mappingDisabled = 'BIOMETRIC_MAPPING_DISABLED';

  /// 410 from the status endpoint — never a login refusal.
  static const String loginAttemptExpired = 'BIOMETRIC_LOGIN_ATTEMPT_EXPIRED';
}

/// A `BIOMETRIC_*` 403 on the palletizer login (§4.2).
class BiometricDenial {
  /// `error.code`.
  final String code;

  /// `error.message` — Arabic, displayed verbatim.
  final String message;
  final int validitySeconds;
  final bool attemptAvailable;

  /// Secret — see the library comment.
  final String? attemptToken;

  /// UTC. Informational only: expiry is decided by the server's 410.
  final DateTime? attemptExpiresAt;
  final String? statusPath;

  const BiometricDenial({
    required this.code,
    required this.message,
    this.validitySeconds = 0,
    this.attemptAvailable = false,
    this.attemptToken,
    this.attemptExpiresAt,
    this.statusPath,
  });

  /// `MAPPING_MISSING` / `MAPPING_DISABLED` — only a SYSTEM_ADMIN can fix it.
  bool get isMappingProblem =>
      code == BiometricCodes.mappingMissing ||
      code == BiometricCodes.mappingDisabled;

  bool get isDeviceUnavailable => code == BiometricCodes.deviceUnavailable;

  /// An attempt the app can poll: recoverable and a token is present.
  bool get canPoll =>
      !isMappingProblem &&
      attemptAvailable &&
      attemptToken != null &&
      attemptToken!.isNotEmpty;

  @override
  String toString() =>
      'BiometricDenial($code, attemptAvailable: $attemptAvailable)';
}

/// `data.status` of `GET /auth/biometric/login-attempts/status` (§4.3).
enum BiometricAttemptStatus {
  pending,
  verified,
  enforcementSuspended,
  notRequired,
  deviceUnavailable,
  mappingMissing,
  mappingDisabled;

  /// Unknown or missing values map to [pending], so a future server value
  /// never breaks the dialog.
  static BiometricAttemptStatus fromWire(Object? raw) {
    switch (raw) {
      case 'VERIFIED':
        return verified;
      case 'ENFORCEMENT_SUSPENDED':
        return enforcementSuspended;
      case 'NOT_REQUIRED':
        return notRequired;
      case 'DEVICE_UNAVAILABLE':
        return deviceUnavailable;
      case 'MAPPING_MISSING':
        return mappingMissing;
      case 'MAPPING_DISABLED':
        return mappingDisabled;
      default:
        return pending;
    }
  }

  /// The original login must be re-submitted once.
  bool get allowsResubmit =>
      this == verified || this == enforcementSuspended || this == notRequired;

  bool get isMappingProblem =>
      this == mappingMissing || this == mappingDisabled;
}

class BiometricAttemptStatusResponse {
  final BiometricAttemptStatus status;

  /// UTC. Informational only: expiry is decided by the server's 410.
  final DateTime? attemptExpiresAt;

  const BiometricAttemptStatusResponse({
    required this.status,
    this.attemptExpiresAt,
  });
}

/// Thrown by the palletizer login for a `BIOMETRIC_*` 403. Not a wrong PIN.
///
/// [details] deliberately leave out the attempt token, which only [denial]
/// carries, so logging the exception or its details can never leak it.
class BiometricDenialException extends ApiException {
  final BiometricDenial denial;

  BiometricDenialException(this.denial)
    : super(
        code: denial.code,
        message: denial.message,
        details: {
          'validitySeconds': denial.validitySeconds,
          'attemptAvailable': denial.attemptAvailable,
        },
        statusCode: 403,
      );
}

/// 410 from the status endpoint: the attempt is unknown or expired (the two
/// are indistinguishable by design).
class BiometricAttemptExpiredException extends ApiException {
  BiometricAttemptExpiredException({String? message})
    : super(
        code: BiometricCodes.loginAttemptExpired,
        message: message ?? BiometricLoginStrings.serverLoginAttemptExpired,
        statusCode: 410,
      );
}
