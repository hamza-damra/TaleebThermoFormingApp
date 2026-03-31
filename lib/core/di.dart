import '../data/datasources/api_client.dart';
import '../data/datasources/auth_local_storage.dart';
import '../data/datasources/printing_local_storage.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/palletizing_repository_impl.dart';
import '../data/repositories/preset_repository_impl.dart';
import '../data/repositories/printer_repository_impl.dart';
import '../data/repositories/shift_handover_repository_impl.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/palletizing_repository.dart';
import '../domain/repositories/preset_repository.dart';
import '../domain/repositories/printer_repository.dart';
import '../domain/repositories/shift_handover_repository.dart';
import '../presentation/providers/auth_provider.dart';
import '../presentation/providers/palletizing_provider.dart';
import '../presentation/providers/printing_provider.dart';
import '../presentation/providers/shift_handover_provider.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late ApiClient _apiClient;
  late AuthLocalStorage _authLocalStorage;
  late AuthRepository _authRepository;
  late PalletizingRepository _palletizingRepository;
  late ShiftHandoverRepository _shiftHandoverRepository;
  late PrinterRepository _printerRepository;
  late PresetRepository _presetRepository;

  Future<void> init() async {
    _authLocalStorage = AuthLocalStorage();
    _apiClient = ApiClient(authStorage: _authLocalStorage);

    _authRepository = AuthRepositoryImpl(
      apiClient: _apiClient,
      authStorage: _authLocalStorage,
    );

    _palletizingRepository = PalletizingRepositoryImpl(apiClient: _apiClient);

    _shiftHandoverRepository = ShiftHandoverRepositoryImpl(
      apiClient: _apiClient,
    );

    await PrintingLocalStorage.initialize();
    _printerRepository = PrinterRepositoryImpl();
    _presetRepository = PresetRepositoryImpl();
  }

  AuthProvider createAuthProvider() {
    return AuthProvider(_authRepository);
  }

  PalletizingProvider createPalletizingProvider() {
    return PalletizingProvider(_palletizingRepository);
  }

  PrintingProvider createPrintingProvider() {
    return PrintingProvider(_printerRepository, _presetRepository);
  }

  ShiftHandoverProvider createShiftHandoverProvider() {
    return ShiftHandoverProvider(_shiftHandoverRepository);
  }

  Future<bool> isLoggedIn() async {
    return await _authLocalStorage.hasToken();
  }
}

final serviceLocator = ServiceLocator();
