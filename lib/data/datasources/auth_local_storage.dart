import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthLocalStorage {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userEmailKey = 'user_email';
  static const _userRoleKey = 'user_role';
  static const _deviceKeyKey = 'device_api_key';

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
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: _userIdKey, value: id.toString()),
      _storage.write(key: _userNameKey, value: name),
      _storage.write(key: _userEmailKey, value: email),
      _storage.write(key: _userRoleKey, value: role),
    ]);
  }

  Future<Map<String, String?>> getUserInfo() async {
    final results = await Future.wait([
      _storage.read(key: _userIdKey),
      _storage.read(key: _userNameKey),
      _storage.read(key: _userEmailKey),
      _storage.read(key: _userRoleKey),
    ]);
    return {
      'id': results[0],
      'name': results[1],
      'email': results[2],
      'role': results[3],
    };
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Device Key ──

  Future<void> saveDeviceKey(String key) async {
    await _storage.write(key: _deviceKeyKey, value: key);
  }

  Future<String?> getDeviceKey() async {
    return await _storage.read(key: _deviceKeyKey);
  }

  Future<bool> hasDeviceKey() async {
    final key = await getDeviceKey();
    return key != null && key.isNotEmpty;
  }

  Future<void> clearDeviceKey() async {
    await _storage.delete(key: _deviceKeyKey);
  }

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
