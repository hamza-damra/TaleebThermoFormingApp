import 'package:flutter/foundation.dart';

import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;

  AuthProvider(this._authRepository);

  AuthState _state = AuthState.initial;
  User? _user;
  String? _errorMessage;

  AuthState get state => _state;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isLoading => _state == AuthState.loading;

  Future<void> checkAuthStatus() async {
    _state = AuthState.loading;
    notifyListeners();

    try {
      final isLoggedIn = await _authRepository.isLoggedIn();
      if (isLoggedIn) {
        _user = await _authRepository.getCurrentUser();
        _state = AuthState.authenticated;
      } else {
        _state = AuthState.unauthenticated;
      }
    } catch (e) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authRepository.login(email: email, password: password);
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _state = AuthState.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'حدث خطأ غير متوقع';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> pinLogin({required String employeeCode}) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authRepository.pinLogin(employeeCode: employeeCode);
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.displayMessage;
      _state = AuthState.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'حدث خطأ غير متوقع';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    _user = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }
}
