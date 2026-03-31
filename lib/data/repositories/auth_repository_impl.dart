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

  static const _allowedRoles = {'PALLETIZER', 'DRIVER', 'OFFICER'};

  @override
  Future<User> login({required String email, required String password}) async {
    final response = await _apiClient.request<Map<String, dynamic>>(
      path: '/auth/login',
      method: 'POST',
      data: {'email': email, 'password': password},
      parser: (json) => json['data'] as Map<String, dynamic>,
    );

    final token = response['token'] as String;
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);

    if (!_allowedRoles.contains(user.role)) {
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
      role: user.role,
    );

    return user;
  }

  @override
  Future<User> pinLogin({required String employeeCode}) async {
    final response = await _apiClient.request<Map<String, dynamic>>(
      path: '/auth/pin-login',
      method: 'POST',
      data: {'employeeCode': employeeCode},
      parser: (json) => json['data'] as Map<String, dynamic>,
    );

    final token = response['token'] as String;
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);

    if (!_allowedRoles.contains(user.role)) {
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
      role: user.role,
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
    final idStr = userInfo['id'];
    if (idStr == null) return null;

    return User(
      id: int.parse(idStr),
      name: userInfo['name'] ?? '',
      email: userInfo['email'] ?? '',
      role: userInfo['role'] ?? '',
    );
  }
}
