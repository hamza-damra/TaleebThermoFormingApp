import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/biometric_login.dart';

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _asString(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _asInstant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

class BiometricDenialModel extends BiometricDenial {
  const BiometricDenialModel({
    required super.code,
    required super.message,
    super.validitySeconds,
    super.attemptAvailable,
    super.attemptToken,
    super.attemptExpiresAt,
    super.statusPath,
  });

  /// The typed denial for a login refused with a 403 whose `error.code` is a
  /// `BIOMETRIC_*` code, else `null` (every other refusal keeps its handling).
  static BiometricDenialModel? fromApiException(ApiException e) {
    if (e.statusCode != 403) return null;
    if (!e.code.startsWith(BiometricCodes.prefix)) return null;
    if (e.code == BiometricCodes.loginAttemptExpired) return null;
    final details = e.details ?? const <String, dynamic>{};
    final token = _asString(details['attemptToken']);
    final available = details['attemptAvailable'];
    return BiometricDenialModel(
      code: e.code,
      message: e.message,
      validitySeconds: _asInt(details['validitySeconds']) ?? 0,
      attemptAvailable: available is bool ? available : token != null,
      attemptToken: token,
      attemptExpiresAt: _asInstant(details['attemptExpiresAt']),
      statusPath: _asString(details['statusPath']),
    );
  }
}

class BiometricAttemptStatusResponseModel
    extends BiometricAttemptStatusResponse {
  const BiometricAttemptStatusResponseModel({
    required super.status,
    super.attemptExpiresAt,
  });

  factory BiometricAttemptStatusResponseModel.fromJson(
    Map<String, dynamic>? json,
  ) {
    return BiometricAttemptStatusResponseModel(
      status: BiometricAttemptStatus.fromWire(json?['status']),
      attemptExpiresAt: _asInstant(json?['attemptExpiresAt']),
    );
  }
}
