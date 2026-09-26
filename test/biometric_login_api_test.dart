// Biometric login gate — API client / repository / model tests.
//
// Contract: docs/FRONTEND_HANDOFF_PALLETIZING_APP_BIOMETRIC_LOGIN_GATE.md
//   * a `BIOMETRIC_*` 403 on palletizer-auth is a typed BiometricDenial, and
//     every other 403 keeps its current handling (§4.4, §7);
//   * the status long-poll sends only `X-Biometric-Attempt-Token`, waits at
//     least 35 s, resolves `statusPath` on the login's origin and maps 410 to
//     an expired attempt (§4.3, §7);
//   * the attempt token never reaches a log (§6, §12).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/config.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/models/biometric_login_model.dart';
import 'package:taleeb_thermoforming/data/repositories/biometric_login_repository_impl.dart';
import 'package:taleeb_thermoforming/data/repositories/palletizing_repository_impl.dart';
import 'package:taleeb_thermoforming/domain/entities/biometric_login.dart';

const _token = 'q3Jx8d6cYt0H1m0yF3kZ0wS9gQx8B7nV2rP5aL4eK1c';
const _statusPath = '/api/v1/auth/biometric/login-attempts/status';

class _Storage extends AuthLocalStorage {
  @override
  Future<String?> getDeviceKey() async => 'test-device-key';

  /// A JWT is stored — the status call must still not send it.
  @override
  Future<String?> getToken() async => 'stored-jwt';
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body, {this.hang = false});

  final int status;
  final Object? body;

  /// Never answers; fails only when the request is cancelled.
  final bool hang;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (hang) {
      final never = Completer<ResponseBody>();
      cancelFuture?.then((_) {
        if (!never.isCompleted) {
          never.completeError(
            DioException.requestCancelled(
              requestOptions: options,
              reason: 'cancelled',
            ),
          );
        }
      });
      return never.future;
    }
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _refusal(String code, Map<String, dynamic> details) => {
  'success': false,
  'error': {'code': code, 'message': 'رسالة الخادم', 'details': details},
};

Map<String, dynamic> _tokenDetails() => {
  'validitySeconds': 300,
  'attemptToken': _token,
  'attemptExpiresAt': '2026-09-24T08:15:00.000Z',
  'statusPath': _statusPath,
  'attemptAvailable': true,
};

Map<String, dynamic> _status(String status) => {
  'success': true,
  'data': {'status': status, 'attemptExpiresAt': '2026-09-24T08:15:00.000Z'},
};

ApiClient _client(_CannedAdapter adapter) {
  final client = ApiClient(authStorage: _Storage());
  client.dio.httpClientAdapter = adapter;
  return client;
}

Future<Object> _loginError(int status, Object? body) async {
  final repo = PalletizingRepositoryImpl(
    apiClient: _client(_CannedAdapter(status, body)),
  );
  try {
    await repo.palletizerAuth(lineId: 3, pin: '1234');
  } catch (e) {
    return e;
  }
  fail('expected the login to fail');
}

/// Captures everything sent to `debugPrint` until the test ends.
List<String> _captureLogs() {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  addTearDown(() => debugPrint = original);
  return logs;
}

void main() {
  group('palletizer-auth refusals', () {
    test('403 VERIFICATION_REQUIRED with a token is a typed denial', () async {
      final e = await _loginError(
        403,
        _refusal(BiometricCodes.verificationRequired, _tokenDetails()),
      );

      expect(e, isA<BiometricDenialException>());
      final denial = (e as BiometricDenialException).denial;
      expect(denial.code, BiometricCodes.verificationRequired);
      expect(denial.message, 'رسالة الخادم');
      expect(denial.validitySeconds, 300);
      expect(denial.attemptAvailable, isTrue);
      expect(denial.attemptToken, _token);
      expect(denial.attemptExpiresAt, DateTime.utc(2026, 9, 24, 8, 15));
      expect(denial.attemptExpiresAt!.isUtc, isTrue);
      expect(denial.statusPath, _statusPath);
      expect(denial.canPoll, isTrue);
      expect(denial.isMappingProblem, isFalse);
      // Still an ApiException for any generic handler, but one that can't
      // leak the token through its details or its text.
      expect(e.statusCode, 403);
      expect(e.details!.containsKey('attemptToken'), isFalse);
      expect(e.toString(), isNot(contains(_token)));
      expect(denial.toString(), isNot(contains(_token)));
    });

    test('EXPIRED and DEVICE_UNAVAILABLE carry the same details', () async {
      for (final code in [
        BiometricCodes.verificationExpired,
        BiometricCodes.deviceUnavailable,
      ]) {
        final e = await _loginError(403, _refusal(code, _tokenDetails()));
        final denial = (e as BiometricDenialException).denial;
        expect(denial.code, code);
        expect(denial.canPoll, isTrue);
        expect(
          denial.isDeviceUnavailable,
          code == BiometricCodes.deviceUnavailable,
        );
      }
    });

    test('attemptAvailable=false → no attempt to poll', () async {
      final e = await _loginError(
        403,
        _refusal(BiometricCodes.verificationRequired, {
          'validitySeconds': 300,
          'attemptAvailable': false,
        }),
      );
      final denial = (e as BiometricDenialException).denial;
      expect(denial.attemptAvailable, isFalse);
      expect(denial.attemptToken, isNull);
      expect(denial.canPoll, isFalse);
      expect(denial.isMappingProblem, isFalse);
    });

    test('MAPPING_MISSING / MAPPING_DISABLED need an admin', () async {
      for (final code in [
        BiometricCodes.mappingMissing,
        BiometricCodes.mappingDisabled,
      ]) {
        final e = await _loginError(
          403,
          _refusal(code, {'validitySeconds': 300, 'attemptAvailable': false}),
        );
        final denial = (e as BiometricDenialException).denial;
        expect(denial.isMappingProblem, isTrue);
        expect(denial.canPoll, isFalse);
      }
    });

    test('non-biometric 403s keep their current handling', () async {
      final notAllowed = await _loginError(
        403,
        _refusal('PALLETIZER_NOT_ALLOWED', const {}),
      );
      expect(notAllowed, isNot(isA<BiometricDenialException>()));
      expect((notAllowed as ApiException).code, 'PALLETIZER_NOT_ALLOWED');

      final forbidden = await _loginError(403, {
        'success': false,
        'error': {'code': 'FORBIDDEN', 'message': 'Forbidden'},
      });
      expect((forbidden as ApiException).code, 'DEVICE_KEY_INVALID');

      final wrongPin = await _loginError(401, {
        'success': false,
        'error': {'code': 'OPERATOR_PIN_INVALID', 'message': 'x'},
      });
      expect((wrongPin as ApiException).code, 'OPERATOR_PIN_INVALID');
    });

    test('a BIOMETRIC_ code on a non-403 is not a login denial', () {
      final e = ApiException(
        code: BiometricCodes.verificationRequired,
        message: 'x',
        statusCode: 409,
      );
      expect(BiometricDenialModel.fromApiException(e), isNull);
    });
  });

  group('attempt status long-poll', () {
    test('maps every status value; unknown → PENDING', () async {
      const expected = {
        'PENDING': BiometricAttemptStatus.pending,
        'VERIFIED': BiometricAttemptStatus.verified,
        'ENFORCEMENT_SUSPENDED': BiometricAttemptStatus.enforcementSuspended,
        'NOT_REQUIRED': BiometricAttemptStatus.notRequired,
        'DEVICE_UNAVAILABLE': BiometricAttemptStatus.deviceUnavailable,
        'MAPPING_MISSING': BiometricAttemptStatus.mappingMissing,
        'MAPPING_DISABLED': BiometricAttemptStatus.mappingDisabled,
        'SOMETHING_NEW': BiometricAttemptStatus.pending,
      };
      for (final entry in expected.entries) {
        final repo = BiometricLoginRepositoryImpl(
          apiClient: _client(_CannedAdapter(200, _status(entry.key))),
        );
        final r = await repo.getBiometricAttemptStatus(
          statusPath: _statusPath,
          attemptToken: _token,
        );
        expect(r.status, entry.value, reason: entry.key);
        expect(r.attemptExpiresAt, DateTime.utc(2026, 9, 24, 8, 15));
      }
      expect(
        BiometricAttemptStatusResponseModel.fromJson(null).status,
        BiometricAttemptStatus.pending,
      );
    });

    test('sends only the attempt-token header, with a ≥ 35 s receive '
        'timeout, on the login origin', () async {
      final adapter = _CannedAdapter(200, _status('PENDING'));
      final repo = BiometricLoginRepositoryImpl(apiClient: _client(adapter));

      await repo.getBiometricAttemptStatus(
        statusPath: _statusPath,
        attemptToken: _token,
      );

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.headers['X-Biometric-Attempt-Token'], _token);
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('X-Device-Key'), isFalse);
      expect(
        request.receiveTimeout!,
        greaterThanOrEqualTo(const Duration(seconds: 35)),
      );
      final base = Uri.parse(AppConfig.baseUrl);
      expect(request.uri.origin, base.origin);
      // Resolved from the host root: the base URL's /api/v1 is not doubled.
      expect(request.uri.path, _statusPath);
      // The token never goes into the URL.
      expect(request.uri.toString(), isNot(contains(_token)));
    });

    test('a statusPath off the login origin is never used', () async {
      for (final hostile in [
        'https://evil.example/steal',
        '//evil.example/steal',
        'relative/path',
        null,
      ]) {
        final adapter = _CannedAdapter(200, _status('PENDING'));
        final repo = BiometricLoginRepositoryImpl(apiClient: _client(adapter));
        await repo.getBiometricAttemptStatus(
          statusPath: hostile,
          attemptToken: _token,
        );
        final uri = adapter.requests.single.uri;
        expect(uri.origin, Uri.parse(AppConfig.baseUrl).origin);
        expect(uri.path, BiometricLoginRepositoryImpl.defaultStatusPath);
      }
    });

    test('410 → the attempt expired', () async {
      final repo = BiometricLoginRepositoryImpl(
        apiClient: _client(
          _CannedAdapter(410, {
            'success': false,
            'error': {
              'code': BiometricCodes.loginAttemptExpired,
              'message':
                  'انتهت مهلة محاولة الدخول. يرجى تسجيل الدخول مرة أخرى.',
            },
          }),
        ),
      );
      await expectLater(
        repo.getBiometricAttemptStatus(
          statusPath: _statusPath,
          attemptToken: _token,
        ),
        throwsA(isA<BiometricAttemptExpiredException>()),
      );

      final bare = BiometricLoginRepositoryImpl(
        apiClient: _client(_CannedAdapter(410, null)),
      );
      await expectLater(
        bare.getBiometricAttemptStatus(
          statusPath: _statusPath,
          attemptToken: _token,
        ),
        throwsA(isA<BiometricAttemptExpiredException>()),
      );
    });

    test('other failures are plain errors, not an expiry', () async {
      final repo = BiometricLoginRepositoryImpl(
        apiClient: _client(_CannedAdapter(503, null)),
      );
      await expectLater(
        repo.getBiometricAttemptStatus(
          statusPath: _statusPath,
          attemptToken: _token,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e is BiometricAttemptExpiredException,
            'expired',
            isFalse,
          ),
        ),
      );
    });

    test('the cancel signal aborts a held long-poll', () async {
      final adapter = _CannedAdapter(200, null, hang: true);
      final repo = BiometricLoginRepositoryImpl(apiClient: _client(adapter));
      final cancel = Completer<void>();

      final call = repo.getBiometricAttemptStatus(
        statusPath: _statusPath,
        attemptToken: _token,
        cancelSignal: cancel.future,
      );
      cancel.complete();

      await expectLater(call, throwsA(isA<ApiException>()));
    });
  });

  test('the attempt token never reaches the log sink', () async {
    final logs = _captureLogs();

    await _loginError(
      403,
      _refusal(BiometricCodes.verificationRequired, _tokenDetails()),
    );
    for (final status in ['PENDING', 'VERIFIED']) {
      await BiometricLoginRepositoryImpl(
        apiClient: _client(_CannedAdapter(200, _status(status))),
      ).getBiometricAttemptStatus(
        statusPath: _statusPath,
        attemptToken: _token,
      );
    }
    try {
      await BiometricLoginRepositoryImpl(
        apiClient: _client(_CannedAdapter(410, null)),
      ).getBiometricAttemptStatus(
        statusPath: _statusPath,
        attemptToken: _token,
      );
    } on ApiException catch (e) {
      debugPrint('status failed: $e');
    }

    expect(logs, isNotEmpty, reason: 'debug builds log every request');
    expect(logs.where((l) => l.contains(_token)), isEmpty);
  });
}
