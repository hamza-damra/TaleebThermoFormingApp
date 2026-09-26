import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/biometric_login.dart';
import '../../domain/repositories/biometric_login_repository.dart';
import '../datasources/api_client.dart';
import '../models/biometric_login_model.dart';

class BiometricLoginRepositoryImpl implements BiometricLoginRepository {
  final ApiClient _apiClient;

  BiometricLoginRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  /// Used when a denial carries no usable `statusPath`.
  static const String defaultStatusPath =
      '${AppConfig.apiPrefix}/auth/biometric/login-attempts/status';

  @override
  Future<BiometricAttemptStatusResponse> getBiometricAttemptStatus({
    required String? statusPath,
    required String attemptToken,
    Future<void>? cancelSignal,
  }) async {
    final cancelToken = CancelToken();
    cancelSignal?.whenComplete(cancelToken.cancel);
    try {
      return await _apiClient.request<BiometricAttemptStatusResponse>(
        path: statusUrl(statusPath),
        method: 'GET',
        anonymous: true,
        headers: {'X-Biometric-Attempt-Token': attemptToken},
        receiveTimeout: AppConfig.biometricStatusReceiveTimeout,
        cancelToken: cancelToken,
        parser: (json) => BiometricAttemptStatusResponseModel.fromJson(
          json['data'] as Map<String, dynamic>?,
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 410 || e.code == BiometricCodes.loginAttemptExpired) {
        throw BiometricAttemptExpiredException(
          message: e.code == BiometricCodes.loginAttemptExpired
              ? e.message
              : null,
        );
      }
      rethrow;
    }
  }

  /// `statusPath` is host-rooted (`/api/v1/...`) and is resolved against the
  /// login's origin — the API base URL already ends with the prefix, so a
  /// plain concatenation would double it. Anything that does not stay on
  /// that origin falls back to [defaultStatusPath]: the attempt token must
  /// never be sent to another host.
  String statusUrl(String? statusPath) {
    final base = Uri.parse(_apiClient.dio.options.baseUrl);
    final fallback = base.resolve(defaultStatusPath).toString();
    final path = statusPath?.trim();
    if (path == null || !path.startsWith('/') || path.startsWith('//')) {
      return fallback;
    }
    try {
      final resolved = base.resolve(path);
      return resolved.origin == base.origin ? resolved.toString() : fallback;
    } on FormatException {
      return fallback;
    }
  }
}
