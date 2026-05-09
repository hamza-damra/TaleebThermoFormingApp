import '../data/datasources/api_client.dart';
import '../data/datasources/auth_local_storage.dart';
import '../data/datasources/printing_local_storage.dart';
import '../data/repositories/palletizing_repository_impl.dart';
import '../data/repositories/preset_repository_impl.dart';
import '../data/repositories/printer_repository_impl.dart';
import '../domain/repositories/palletizing_repository.dart';
import '../domain/repositories/preset_repository.dart';
import '../domain/repositories/printer_repository.dart';
import '../presentation/providers/palletizing_provider.dart';
import '../presentation/providers/printing_provider.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late ApiClient _apiClient;
  late AuthLocalStorage _authLocalStorage;
  late PalletizingRepository _palletizingRepository;
  late PrinterRepository _printerRepository;
  late PresetRepository _presetRepository;

  Future<void> init() async {
    _authLocalStorage = AuthLocalStorage();
    _apiClient = ApiClient(authStorage: _authLocalStorage);

    _palletizingRepository = PalletizingRepositoryImpl(apiClient: _apiClient);

    await PrintingLocalStorage.initialize();
    _printerRepository = PrinterRepositoryImpl();
    _presetRepository = PresetRepositoryImpl();
  }

  PalletizingProvider createPalletizingProvider() {
    return PalletizingProvider(_palletizingRepository, _authLocalStorage);
  }

  PrintingProvider createPrintingProvider() {
    return PrintingProvider(_printerRepository, _presetRepository);
  }
}

final serviceLocator = ServiceLocator();
