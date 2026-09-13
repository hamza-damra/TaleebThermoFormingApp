import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/api_client.dart';
import '../datasources/auth_local_storage.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ApiClient _apiClient;
  final AuthLocalStorage _authStorage;

  AuthRepositoryImpl({
    required ApiClient apiClient,
    required AuthLocalStorage authStorage,
  }) : _apiClient = apiClient,
       _authStorage = authStorage;

  /// The admission set for this app's identity surface. This is a UX courtesy
  /// that produces one clear Arabic message instead of a string of 403s — the
  /// real boundary is server-side on every endpoint.
  static const _allowedRoles = {'DRIVER', 'OFFICER'};

  @override
  Future<User> login({required String email, required String password}) async {
    final response = await _apiClient.request<Map<String, dynamic>>(
      path: '/auth/login',
      method: 'POST',
      data: {'email': email, 'password': password},
      parser: (json) => json['data'] as Map<String, dynamic>,
    );

    return _admit(response);
  }

  @override
  Future<User> pinLogin({required String employeeCode}) async {
    final response = await _apiClient.request<Map<String, dynamic>>(
      path: '/auth/pin-login',
      method: 'POST',
      data: {'employeeCode': employeeCode},
      parser: (json) => json['data'] as Map<String, dynamic>,
    );

    return _admit(response);
  }

  /// Decodes, gates and persists an identity payload. Both login paths share
  /// this so the gate cannot drift between them.
  Future<User> _admit(Map<String, dynamic> response) async {
    final token = response['token'] as String;
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);

    // The complete assigned set is the question — a person entitled through
    // DRIVER must be admitted even when their scoped singular value names
    // something else.
    if (!user.roles.any(_allowedRoles.contains)) {
      throw ApiException(
        code: 'ROLE_NOT_ALLOWED',
        message: 'ليس لديك صلاحية استخدام هذا التطبيق',
      );
    }

    await _authStorage.saveToken(token);
    await _authStorage.saveUserInfo(
      id: user.id,
      name: user.name,
      email: user.email,
      primaryRole: user.primaryRole,
      roles: user.roles,
    );

    return user;
  }

  @override
  Future<void> logout() async {
    await _authStorage.clearAll();
  }

  @override
  Future<bool> isLoggedIn() async {
    return await _authStorage.hasToken();
  }

  @override
  Future<User?> getCurrentUser() async {
    final userInfo = await _authStorage.getUserInfo();
    final idStr = userInfo['id'] as String?;
    final primaryRole = userInfo['primaryRole'] as String?;
    final roles = userInfo['roles'] as List<String>?;
    final id = idStr == null ? null : int.tryParse(idStr);

    // A session persisted by a pre-Wave-8 build carries no normalized identity.
    // Invalidate it rather than reconstructing it: synthesising a set from a
    // singular value would drop a second role for exactly the dual-role people
    // the gate most needs to admit.
    if (id == null ||
        primaryRole == null ||
        primaryRole.isEmpty ||
        roles == null ||
        roles.isEmpty) {
      await _authStorage.clearAll();
      return null;
    }

    return User(
      id: id,
      name: userInfo['name'] as String? ?? '',
      email: userInfo['email'] as String? ?? '',
      primaryRole: primaryRole,
      roles: roles,
    );
  }
}
