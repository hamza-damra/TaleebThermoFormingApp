// Clean-backend identity probe through the production classes end to end: the
// real ApiClient Dio pipeline, AuthRepositoryImpl, and AuthLocalStorage backed
// by an in-memory flutter_secure_storage channel. The envelopes are the exact
// shape a local cutover backend sends (captured with the singular `role`
// already removed; only the token is replaced by a placeholder).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/repositories/auth_repository_impl.dart';
import 'package:taleeb_thermoforming/presentation/providers/auth_provider.dart';

const String _multiRoleEnvelope =
    '{"success":true,"data":{"token":"header.payload.signature","user":'
    '{"email":"w11s4.multi.784310@local.test","id":52,"name":"W11S4 Smoke Multi",'
    '"primaryRole":"OFFICER","roles":["DRIVER","OFFICER"]}}}';
const String _driverEnvelope =
    '{"success":true,"data":{"token":"header.payload.signature","user":'
    '{"email":"driver@local.test","id":53,"name":"Driver",'
    '"primaryRole":"DRIVER","roles":["DRIVER"]}}}';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, String> _installSecureStore() {
  final store = <String, String>{};
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    final args = (call.arguments as Map?) ?? const {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key!] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'containsKey':
        return store.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  return store;
}

class _EnvelopeAdapter implements HttpClientAdapter {
  _EnvelopeAdapter(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = bodies[options.path] ?? '{"success":false}';
    return ResponseBody.fromBytes(
      utf8.encode(body),
      bodies.containsKey(options.path) ? 200 : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A fresh object graph over the shared secure store — which is exactly what a
/// cold start is.
AuthRepositoryImpl _repo(Map<String, String> bodies) {
  final storage = AuthLocalStorage();
  final client = ApiClient(authStorage: storage);
  client.dio.httpClientAdapter = _EnvelopeAdapter(bodies);
  return AuthRepositoryImpl(apiClient: client, authStorage: storage);
}

void main() {
  late Map<String, String> store;

  setUp(() {
    store = _installSecureStore();
  });

  test('the clean-backend envelopes carry no singular role', () {
    for (final raw in [_multiRoleEnvelope, _driverEnvelope]) {
      final user = ((jsonDecode(raw) as Map)['data'] as Map)['user'] as Map;
      expect(user.containsKey('role'), isFalse);
      expect(user.containsKey('permissions'), isFalse);
    }
  });

  test('multi-role PIN login persists the full set and survives a cold '
      'start', () async {
    final signIn = AuthProvider(_repo({'/auth/pin-login': _multiRoleEnvelope}));
    expect(await signIn.pinLogin(employeeCode: '1234'), isTrue);
    expect(signIn.user!.roles.toSet(), {'DRIVER', 'OFFICER'});
    expect(signIn.user!.primaryRole, 'OFFICER');

    expect(store.containsKey('user_role'), isFalse);
    expect(store['user_primary_role'], 'OFFICER');
    expect((jsonDecode(store['user_roles']!) as List).toSet(), {
      'DRIVER',
      'OFFICER',
    });
    expect(store['auth_token'], 'header.payload.signature');

    final restored = AuthProvider(_repo(const {}));
    await restored.checkAuthStatus();

    expect(restored.state, AuthState.authenticated);
    expect(restored.user, equals(signIn.user));
    expect(restored.user!.roles.toSet(), {'DRIVER', 'OFFICER'});
  });

  test('single-role password login persists and restores', () async {
    final signIn = AuthProvider(_repo({'/auth/login': _driverEnvelope}));
    expect(await signIn.login(email: 'd@local.test', password: 'pw'), isTrue);

    final restored = AuthProvider(_repo(const {}));
    await restored.checkAuthStatus();

    expect(restored.state, AuthState.authenticated);
    expect(restored.user!.roles, ['DRIVER']);
    expect(restored.user!.primaryRole, 'DRIVER');
  });

  test('a session stored by the pre-cutover build is invalidated through the '
      'real storage', () async {
    store.addAll({
      'auth_token': 'stale-token',
      'user_id': '42',
      'user_name': 'أحمد',
      'user_email': 'ahmad@taleeb.ps',
      'user_role': 'OFFICER',
    });

    final restored = AuthProvider(_repo(const {}));
    await restored.checkAuthStatus();

    expect(restored.state, AuthState.unauthenticated);
    expect(restored.user, isNull);
    expect(store, isEmpty);
  });
}
