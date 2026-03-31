import '../entities/user.dart';

abstract class AuthRepository {
  Future<User> login({required String email, required String password});
  Future<User> pinLogin({required String employeeCode});
  Future<void> logout();
  Future<bool> isLoggedIn();
  Future<User?> getCurrentUser();
}
