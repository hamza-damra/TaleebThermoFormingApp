import 'package:flutter/foundation.dart';

import '../../core/constants/printing_constants.dart';
import '../../core/exceptions/printing_exception.dart';
import '../../data/datasources/printing_local_storage.dart';
import '../../data/models/printing_settings_model.dart';
import '../../domain/entities/label_preset.dart';
import '../../domain/entities/print_job.dart';
import '../../domain/entities/printer_config.dart';
import '../../domain/repositories/preset_repository.dart';
import '../../domain/repositories/printer_repository.dart';
import '../../printing/printer_client.dart';

enum PrintingState { idle, loading, printing, success, error }

class PrintingProvider extends ChangeNotifier {
  final PrinterRepository _printerRepository;
  final PresetRepository _presetRepository;

  PrintingProvider(this._printerRepository, this._presetRepository);

  PrintingState _state = PrintingState.idle;
  String? _errorMessage;
  List<PrinterConfig> _printers = [];
  List<LabelPreset> _presets = [];
  PrinterConfig? _selectedPrinter;
  LabelPreset? _selectedPreset;
  String? _lastPrintedValue;

  PrintingState get state => _state;
  String? get errorMessage => _errorMessage;
  List<PrinterConfig> get printers => _printers;
  List<LabelPreset> get presets => _presets;
  PrinterConfig? get selectedPrinter => _selectedPrinter;
  LabelPreset? get selectedPreset => _selectedPreset;
  String? get lastPrintedValue => _lastPrintedValue;
  bool get isLoading => _state == PrintingState.loading;
  bool get isPrinting => _state == PrintingState.printing;
  bool get hasPrinters => _printers.isNotEmpty;
  bool get hasSelectedPrinter => _selectedPrinter != null;

  Future<void> loadData() async {
    _state = PrintingState.loading;
    notifyListeners();

    try {
      _printers = _printerRepository.getAll();
      _presets = _presetRepository.getAll();

      final settings = PrintingLocalStorage.getSettings();

      if (settings.lastPrinterId != null) {
        _selectedPrinter = _printerRepository.getById(settings.lastPrinterId!);
      }
      _selectedPrinter ??= _printerRepository.getDefault();

      if (settings.lastPresetId != null) {
        _selectedPreset = _presetRepository.getById(settings.lastPresetId!);
      }
      _selectedPreset ??= DefaultPresets.getById(
        PrintingConstants.defaultPresetId,
      );
      _selectedPreset ??= DefaultPresets.preset50x30;

      _state = PrintingState.idle;
    } catch (e) {
      _errorMessage = 'فشل في تحميل بيانات الطباعة';
      _state = PrintingState.error;
    }
    notifyListeners();
  }

  void selectPrinter(PrinterConfig? printer) {
    _selectedPrinter = printer;
    if (printer != null) {
      _saveSettings();
    }
    notifyListeners();
  }

  void selectPreset(LabelPreset? preset) {
    _selectedPreset = preset;
    if (preset != null) {
      _saveSettings();
    }
    notifyListeners();
  }

  Future<PrintResult> print({
    required String scannedValue,
    int copies = 1,
  }) async {
    if (_selectedPrinter == null) {
      return PrintResult.error('لم يتم اختيار طابعة');
    }

    if (_selectedPreset == null) {
      return PrintResult.error('لم يتم اختيار حجم الملصق');
    }

    _state = PrintingState.printing;
    _errorMessage = null;
    _lastPrintedValue = scannedValue;
    notifyListeners();

    try {
      final client = PrinterClient(_selectedPrinter!);
      await client.print(
        value: scannedValue,
        preset: _selectedPreset!,
        copies: copies,
      );

      _state = PrintingState.success;
      notifyListeners();
      return PrintResult.success();
    } on PrintingException catch (e) {
      _errorMessage = e.displayMessage;
      _state = PrintingState.error;
      notifyListeners();
      return PrintResult.error(e.displayMessage);
    } catch (e) {
      _errorMessage = 'فشل في الطباعة';
      _state = PrintingState.error;
      notifyListeners();
      return PrintResult.error('فشل في الطباعة');
    }
  }

  Future<PrintResult> retryPrint({int copies = 1}) async {
    if (_lastPrintedValue == null) {
      return PrintResult.error('لا توجد قيمة للطباعة');
    }
    return print(scannedValue: _lastPrintedValue!, copies: copies);
  }

  Future<bool> testConnection(PrinterConfig printer) async {
    try {
      final client = PrinterClient(printer);
      return await client.testConnection();
    } catch (_) {
      return false;
    }
  }

  Future<void> addPrinter(PrinterConfig printer) async {
    await _printerRepository.save(printer);
    _printers = _printerRepository.getAll();

    if (_selectedPrinter == null) {
      _selectedPrinter = printer;
      await _saveSettings();
    }
    notifyListeners();
  }

  Future<void> updatePrinter(PrinterConfig printer) async {
    await _printerRepository.save(printer);
    _printers = _printerRepository.getAll();

    if (_selectedPrinter?.id == printer.id) {
      _selectedPrinter = printer;
    }
    notifyListeners();
  }

  Future<void> deletePrinter(String id) async {
    await _printerRepository.delete(id);
    _printers = _printerRepository.getAll();

    if (_selectedPrinter?.id == id) {
      _selectedPrinter = _printerRepository.getDefault();
      await _saveSettings();
    }
    notifyListeners();
  }

  Future<void> setDefaultPrinter(String id) async {
    await _printerRepository.setDefault(id);
    _printers = _printerRepository.getAll();
    notifyListeners();
  }

  Future<void> addPreset(LabelPreset preset) async {
    await _presetRepository.save(preset);
    _presets = _presetRepository.getAll();
    notifyListeners();
  }

  Future<void> updatePreset(LabelPreset preset) async {
    await _presetRepository.save(preset);
    _presets = _presetRepository.getAll();
    if (_selectedPreset?.id == preset.id) {
      _selectedPreset = preset;
    }
    notifyListeners();
  }

  Future<void> deletePreset(String id) async {
    await _presetRepository.delete(id);
    _presets = _presetRepository.getAll();
    if (_selectedPreset?.id == id) {
      _selectedPreset = DefaultPresets.preset50x30;
      await _saveSettings();
    }
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == PrintingState.error) {
      _state = PrintingState.idle;
    }
    notifyListeners();
  }

  void resetState() {
    _state = PrintingState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final settings = PrintingSettingsModel(
      lastPrinterId: _selectedPrinter?.id,
      lastPresetId: _selectedPreset?.id,
    );
    await PrintingLocalStorage.saveSettings(settings);
  }
}
