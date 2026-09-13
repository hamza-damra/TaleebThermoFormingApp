import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthLocalStorage {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userEmailKey = 'user_email';

  /// The normalized Wave-8 identity shape. There is no singular-role key: the
  /// complete set and the scoped singular value are the only two stored role
  /// signals, so there is never a second source of the same truth.
  static const _userRolesKey = 'user_roles';
  static const _userPrimaryRoleKey = 'user_primary_role';

  final FlutterSecureStorage _storage;

  AuthLocalStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> saveUserInfo({
    required int id,
    required String name,
    required String email,
    required String primaryRole,
    required List<String> roles,
  }) async {
    await Future.wait([
      _storage.write(key: _userIdKey, value: id.toString()),
      _storage.write(key: _userNameKey, value: name),
      _storage.write(key: _userEmailKey, value: email),
      _storage.write(key: _userPrimaryRoleKey, value: primaryRole),
      _storage.write(key: _userRolesKey, value: jsonEncode(roles)),
    ]);
  }

  /// Returns `roles` as a decoded `List<String>` and every other field as a
  /// `String`. `roles` is null when the key is absent or unreadable — which is
  /// how a session persisted by a pre-Wave-8 build presents itself, and what
  /// the caller uses to invalidate it.
  Future<Map<String, dynamic>> getUserInfo() async {
    final results = await Future.wait([
      _storage.read(key: _userIdKey),
      _storage.read(key: _userNameKey),
      _storage.read(key: _userEmailKey),
      _storage.read(key: _userPrimaryRoleKey),
      _storage.read(key: _userRolesKey),
    ]);
    return {
      'id': results[0],
      'name': results[1],
      'email': results[2],
      'primaryRole': results[3],
      'roles': _decodeRoles(results[4]),
    };
  }

  static List<String>? _decodeRoles(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Device Key (static) ──

  static const String _staticDeviceKey = 'taleeb-device-key-2025-default';

  Future<void> saveDeviceKey(String key) async {}

  Future<String?> getDeviceKey() async => _staticDeviceKey;

  Future<bool> hasDeviceKey() async => true;

  Future<void> clearDeviceKey() async {}

  // ── Palletizer Session Token (per backend lineId) ──
  // Keys are namespaced by backend lineId, not UI lineNumber, so storage stays
  // aligned with the API and tolerates any tab re-indexing.
  static String _palletizerSessionTokenKey(int lineId) =>
      'palletizer_session_token_$lineId';

  Future<void> savePalletizerSessionToken(int lineId, String token) async {
    await _storage.write(key: _palletizerSessionTokenKey(lineId), value: token);
  }

  Future<String?> getPalletizerSessionToken(int lineId) async {
    return await _storage.read(key: _palletizerSessionTokenKey(lineId));
  }

  Future<void> clearPalletizerSessionToken(int lineId) async {
    await _storage.delete(key: _palletizerSessionTokenKey(lineId));
  }
}
