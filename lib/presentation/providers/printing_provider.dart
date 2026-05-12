import 'package:flutter/foundation.dart';

import '../../core/constants/printing_constants.dart';
import '../../core/exceptions/printing_exception.dart';
import '../../data/datasources/printing_local_storage.dart';
import '../../data/models/printing_settings_model.dart';
import '../../domain/entities/label_preset.dart';
import '../../domain/entities/print_result.dart';
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
  String? _lastTopText;
  String? _lastBottomText;
  String? _lastSideText;
  int _copies = 1;

  PrintingState get state => _state;
  String? get errorMessage => _errorMessage;
  List<PrinterConfig> get printers => _printers;
  List<LabelPreset> get presets => _presets;
  PrinterConfig? get selectedPrinter => _selectedPrinter;
  LabelPreset? get selectedPreset => _selectedPreset;
  String? get lastPrintedValue => _lastPrintedValue;
  int get copies => _copies;
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
      _selectedPreset ??= DefaultPresets.defaultPreset;

      _copies = settings.lastCopies.clamp(1, 10);

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
      // Keep the visible preset in sync with the printer's configured size.
      _selectedPreset = resolvePresetFor(printer);
      _saveSettings();
    }
    notifyListeners();
  }

  /// Resolves the [LabelPreset] tied to a printer, falling back to the
  /// built-in default when the printer references an unknown preset id
  /// (e.g. a custom preset that was later deleted).
  LabelPreset resolvePresetFor(PrinterConfig printer) {
    final fromRepo = _presetRepository.getById(printer.labelPresetId);
    if (fromRepo != null) return fromRepo;
    final fromDefaults = DefaultPresets.getById(printer.labelPresetId);
    if (fromDefaults != null) return fromDefaults;
    return DefaultPresets.defaultPreset;
  }

  void selectPreset(LabelPreset? preset) {
    _selectedPreset = preset;
    if (preset != null) {
      _saveSettings();
    }
    notifyListeners();
  }

  void setCopies(int value) {
    _copies = value.clamp(1, 10);
    _saveSettings();
    notifyListeners();
  }

  Future<PrintResult> print({
    required String scannedValue,
    int copies = 1,
    String? topText,
    String? bottomText,
    String? sideText,
  }) async {
    if (_selectedPrinter == null) {
      return PrintResult.error('لم يتم اختيار طابعة');
    }

    // Source of truth for the label size is the printer's own configuration.
    // Falls back to the built-in default if the referenced preset is missing.
    final preset = resolvePresetFor(_selectedPrinter!);
    _selectedPreset = preset;

    _state = PrintingState.printing;
    _errorMessage = null;
    _lastPrintedValue = scannedValue;
    _lastTopText = topText;
    _lastBottomText = bottomText;
    _lastSideText = sideText;
    notifyListeners();

    try {
      final client = PrinterClient(_selectedPrinter!);
      await client.print(
        value: scannedValue,
        preset: preset,
        copies: copies,
        topText: topText,
        bottomText: bottomText,
        sideText: sideText,
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
    return print(
      scannedValue: _lastPrintedValue!,
      copies: copies,
      topText: _lastTopText,
      bottomText: _lastBottomText,
      sideText: _lastSideText,
    );
  }

  Future<bool> testConnection(PrinterConfig printer) async {
    try {
      final client = PrinterClient(printer);
      return await client.testConnection();
    } catch (_) {
      return false;
    }
  }

  /// Sends a small protocol-specific test label. Unlike [testConnection],
  /// this validates that the printer actually understands the configured
  /// language (TSPL vs ZPL) — not just that a socket can be opened.
  Future<PrintResult> testPrint(PrinterConfig printer) async {
    try {
      final preset = resolvePresetFor(printer);
      final client = PrinterClient(printer);
      await client.testPrint(preset: preset);
      return PrintResult.success();
    } on PrintingException catch (e) {
      return PrintResult.error(e.displayMessage);
    } catch (_) {
      return PrintResult.error('فشل إرسال اختبار الطباعة');
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

  Future<LabelPreset> addPreset(LabelPreset preset) async {
    final saved = await _presetRepository.save(preset);
    _presets = _presetRepository.getAll();
    notifyListeners();
    return saved;
  }

  Future<LabelPreset> updatePreset(LabelPreset preset) async {
    final saved = await _presetRepository.save(preset);
    _presets = _presetRepository.getAll();
    if (_selectedPreset?.id == saved.id) {
      _selectedPreset = saved;
    }
    notifyListeners();
    return saved;
  }

  Future<void> deletePreset(String id) async {
    await _presetRepository.delete(id);
    _presets = _presetRepository.getAll();
    if (_selectedPreset?.id == id) {
      _selectedPreset = DefaultPresets.defaultPreset;
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
      lastCopies: _copies,
    );
    await PrintingLocalStorage.saveSettings(settings);
  }
}
