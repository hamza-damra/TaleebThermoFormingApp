// Wave-8 identity contract — target-contract fixtures only.
//
// Every payload here is the post-cutover shape: `roles` + `primaryRole`, and no
// singular legacy field. There is intentionally no test asserting that a
// legacy-only payload parses, because no code path may read one.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/models/user_model.dart';
import 'package:taleeb_thermoforming/data/repositories/auth_repository_impl.dart';
import 'package:taleeb_thermoforming/domain/entities/user.dart';
import 'package:taleeb_thermoforming/presentation/providers/auth_provider.dart';

const String kRoleNotAllowedMessage = 'ليس لديك صلاحية استخدام هذا التطبيق';

Map<String, dynamic> userJson({
  List<String> roles = const ['OFFICER', 'DRIVER'],
  String primaryRole = 'OFFICER',
}) => <String, dynamic>{
  'id': 42,
  'name': 'أحمد',
  'email': 'ahmad@taleeb.ps',
  'roles': roles,
  'primaryRole': primaryRole,
};

/// In-memory stand-in for the secure store. Overrides only the human-identity
/// surface; the device key and the per-line session tokens are a separate chain
/// and are left exactly as they are.
class FakeAuthLocalStorage extends AuthLocalStorage {
  final Map<String, String> values = {};
  int clearAllCalls = 0;

  @override
  Future<void> saveToken(String token) async => values['auth_token'] = token;

  @override
  Future<String?> getToken() async => values['auth_token'];

  @override
  Future<bool> hasToken() async {
    final token = values['auth_token'];
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> saveUserInfo({
    required int id,
    required String name,
    required String email,
    required String primaryRole,
    required List<String> roles,
  }) async {
    values['user_id'] = id.toString();
    values['user_name'] = name;
    values['user_email'] = email;
    values['user_primary_role'] = primaryRole;
    values['user_roles'] = jsonEncode(roles);
  }

  @override
  Future<Map<String, dynamic>> getUserInfo() async {
    final rawRoles = values['user_roles'];
    List<String>? decodedRoles;
    if (rawRoles != null && rawRoles.isNotEmpty) {
      final decoded = jsonDecode(rawRoles);
      if (decoded is List) {
        decodedRoles = decoded.whereType<String>().toList(growable: false);
      }
    }
    return {
      'id': values['user_id'],
      'name': values['user_name'],
      'email': values['user_email'],
      'primaryRole': values['user_primary_role'],
      'roles': decodedRoles,
    };
  }

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
    values.clear();
  }
}

/// Returns a canned `data` envelope instead of going to the network.
class FakeApiClient extends ApiClient {
  FakeApiClient(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<String> calledPaths = [];

  @override
  Future<T> request<T>({
    required String path,
    required String method,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool anonymous = false,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    calledPaths.add(path);
    final body = responses[path];
    if (body == null) {
      throw StateError('unexpected path $path');
    }
    return parser({'success': true, 'data': body});
  }
}

({AuthRepositoryImpl repo, FakeAuthLocalStorage storage}) buildRepo(
  Map<String, dynamic> user,
) {
  final storage = FakeAuthLocalStorage();
  final envelope = {'token': 'jwt-token', 'user': user};
  final repo = AuthRepositoryImpl(
    apiClient: FakeApiClient({
      '/auth/login': envelope,
      '/auth/pin-login': envelope,
    }),
    authStorage: storage,
  );
  return (repo: repo, storage: storage);
}

Future<User> loginVia(AuthRepositoryImpl repo, String path) =>
    path == '/auth/login'
    ? repo.login(email: 'ahmad@taleeb.ps', password: 'pw')
    : repo.pinLogin(employeeCode: '1234');

Matcher get _malformedIdentity => throwsA(
  isA<ApiException>().having(
    (e) => e.code,
    'code',
    'IDENTITY_CONTRACT_MALFORMED',
  ),
);

void main() {
  group('model parsing — target fixtures', () {
    test('DRIVER + OFFICER, no legacy key', () {
      final user = UserModel.fromJson(userJson());

      expect(user.roles, containsAll(['OFFICER', 'DRIVER']));
      expect(user.roles.length, 2);
      expect(user.primaryRole, 'OFFICER');
      expect(user.id, 42);
      expect(user.email, 'ahmad@taleeb.ps');
    });

    test('DRIVER only, no legacy key', () {
      final user = UserModel.fromJson(
        userJson(roles: ['DRIVER'], primaryRole: 'DRIVER'),
      );

      expect(user.roles, ['DRIVER']);
      expect(user.primaryRole, 'DRIVER');
    });

    test('reversed roles ordering behaves identically', () {
      final forward = UserModel.fromJson(userJson());
      final reversed = UserModel.fromJson(
        userJson(roles: ['DRIVER', 'OFFICER']),
      );

      expect(reversed.roles.toSet(), forward.roles.toSet());
      expect(reversed.primaryRole, forward.primaryRole);
      // Order is not a contract, so it cannot distinguish two identities.
      expect(reversed, equals(forward));
    });

    test('missing roles is a contract error', () {
      final json = userJson()..remove('roles');

      expect(() => UserModel.fromJson(json), _malformedIdentity);
    });

    test('missing primaryRole is a contract error', () {
      final json = userJson()..remove('primaryRole');

      expect(() => UserModel.fromJson(json), _malformedIdentity);
    });

    test('empty roles is a contract error', () {
      expect(
        () => UserModel.fromJson(userJson(roles: const [])),
        _malformedIdentity,
      );
    });

    test('unknown role names parse and are never coerced', () async {
      final user = UserModel.fromJson(
        userJson(roles: ['DRIVER', 'WAREHOUSE_WIZARD'], primaryRole: 'DRIVER'),
      );

      expect(user.roles, ['DRIVER', 'WAREHOUSE_WIZARD']);

      // An unknown role on its own matches nothing and admits nobody.
      final ctx = buildRepo(
        userJson(roles: ['WAREHOUSE_WIZARD'], primaryRole: 'WAREHOUSE_WIZARD'),
      );
      await expectLater(
        loginVia(ctx.repo, '/auth/login'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'ROLE_NOT_ALLOWED'),
        ),
      );
    });
  });

  group('zero-legacy behavioural ratchet', () {
    test('adding or removing the legacy field changes nothing', () async {
      final without = userJson();
      final withLegacy = userJson()..['role'] = 'OFFICER';

      expect(
        UserModel.fromJson(withLegacy),
        equals(UserModel.fromJson(without)),
      );

      final a = buildRepo(without);
      final b = buildRepo(withLegacy);
      final userA = await loginVia(a.repo, '/auth/login');
      final userB = await loginVia(b.repo, '/auth/login');

      expect(userB, equals(userA));
      expect(b.storage.values, equals(a.storage.values));

      // Removing it again is equally inert.
      final removed = Map<String, dynamic>.from(withLegacy)..remove('role');
      expect(UserModel.fromJson(removed), equals(UserModel.fromJson(without)));
    });
  });

  group('admission gate', () {
    for (final path in const ['/auth/login', '/auth/pin-login']) {
      test('primaryRole outside the set but roles holds DRIVER — admitted '
          'on $path', () async {
        final ctx = buildRepo(
          userJson(roles: ['ACCOUNTANT', 'DRIVER'], primaryRole: 'ACCOUNTANT'),
        );

        final user = await loginVia(ctx.repo, path);

        expect(user.primaryRole, 'ACCOUNTANT');
        expect(user.roles, contains('DRIVER'));
      });

      test('no admissible role — rejected on $path', () async {
        final ctx = buildRepo(
          userJson(roles: ['ACCOUNTANT'], primaryRole: 'ACCOUNTANT'),
        );

        await expectLater(
          loginVia(ctx.repo, path),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'ROLE_NOT_ALLOWED')
                .having((e) => e.message, 'message', kRoleNotAllowedMessage),
          ),
        );
        // A rejected login leaves nothing behind.
        expect(ctx.storage.values, isEmpty);
      });

      test('PALLETIZER is no longer admissible on $path', () async {
        final ctx = buildRepo(
          userJson(roles: ['PALLETIZER'], primaryRole: 'PALLETIZER'),
        );

        await expectLater(
          loginVia(ctx.repo, path),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'ROLE_NOT_ALLOWED',
            ),
          ),
        );
      });
    }
  });

  group('persistence', () {
    test('login writes the normalized shape and no singular value', () async {
      final ctx = buildRepo(userJson());

      await loginVia(ctx.repo, '/auth/login');

      expect(ctx.storage.values.containsKey('user_role'), isFalse);
      expect(ctx.storage.values['user_primary_role'], 'OFFICER');
      expect(jsonDecode(ctx.storage.values['user_roles']!), [
        'OFFICER',
        'DRIVER',
      ]);

      final restored = await ctx.repo.getCurrentUser();
      expect(restored!.roles, ['OFFICER', 'DRIVER']);
      expect(restored.primaryRole, 'OFFICER');
    });

    test('a stale pre-migration session is invalidated', () async {
      final ctx = buildRepo(userJson());
      ctx.storage.values.addAll({
        'auth_token': 'stale-jwt',
        'user_id': '42',
        'user_name': 'أحمد',
        'user_email': 'ahmad@taleeb.ps',
        'user_role': 'OFFICER', // the pre-Wave-8 shape
      });

      final provider = AuthProvider(ctx.repo);
      await provider.checkAuthStatus();

      expect(provider.state, AuthState.unauthenticated);
      expect(provider.user, isNull);
      expect(ctx.storage.clearAllCalls, 1);
      expect(ctx.storage.values, isEmpty);
    });

    test('a normalized session survives cold start', () async {
      final ctx = buildRepo(userJson());
      await loginVia(ctx.repo, '/auth/login');

      final provider = AuthProvider(ctx.repo);
      await provider.checkAuthStatus();

      expect(provider.state, AuthState.authenticated);
      expect(provider.user!.roles, containsAll(['OFFICER', 'DRIVER']));
      expect(ctx.storage.clearAllCalls, 0);
    });

    test('a dual-role user round-trips with both entries', () async {
      final ctx = buildRepo(userJson());

      await loginVia(ctx.repo, '/auth/pin-login');
      final restored = await ctx.repo.getCurrentUser();

      expect(restored!.roles.length, 2);
      expect(restored.roles, containsAll(['OFFICER', 'DRIVER']));
    });

    test('logout clears every identity key', () async {
      final ctx = buildRepo(userJson());
      await loginVia(ctx.repo, '/auth/login');
      expect(ctx.storage.values, isNotEmpty);

      await ctx.repo.logout();

      expect(ctx.storage.values, isEmpty);
      expect(await ctx.repo.isLoggedIn(), isFalse);
    });
  });

  group('mechanical zero-legacy ratchet', () {
    test('no singular identity key remains in lib/', () {
      final offenders = <String>[];
      final pattern = RegExp('([\'"])(role|user_role)\\1');

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = _stripComments(entity.readAsStringSync());
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'legacy identity key found:\n${offenders.join('\n')}',
      );
    });

    test('User exposes no singular-role alias', () {
      const user = User(
        id: 1,
        name: 'n',
        email: 'e',
        primaryRole: 'OFFICER',
        roles: ['OFFICER'],
      );

      // Nothing named after the legacy field exists to alias, so the two
      // contract fields are the only role signals.
      expect((user as dynamic).roles, ['OFFICER']);
      expect(() => (user as dynamic).role, throwsNoSuchMethodError);
    });
  });
}

/// Blanks out line and block comments so prose cannot trip the ratchet, while
/// keeping line numbering intact. A source scan rather than an AST walk, to
/// avoid adding an `analyzer` dependency for a single check.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAllMapped(
    RegExp(r'/\*.*?\*/', dotAll: true),
    (m) => m[0]!.replaceAll(RegExp('[^\n]'), ' '),
  );
  return withoutBlocks
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');
}
