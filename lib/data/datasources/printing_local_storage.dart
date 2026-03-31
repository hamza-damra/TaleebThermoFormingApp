import 'package:hive_flutter/hive_flutter.dart';

import '../models/printer_config_model.dart';
import '../models/label_preset_model.dart';
import '../models/printing_settings_model.dart';

class PrintingLocalStorage {
  static const String _printersBoxName = 'printers';
  static const String _presetsBoxName = 'custom_presets';
  static const String _settingsBoxName = 'printing_settings';
  static const String _settingsKey = 'settings';

  static Box<PrinterConfigModel>? _printersBox;
  static Box<LabelPresetModel>? _presetsBox;
  static Box<PrintingSettingsModel>? _settingsBox;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(PrinterConfigModelAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(LabelPresetModelAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PrintingSettingsModelAdapter());
    }

    _printersBox = await Hive.openBox<PrinterConfigModel>(_printersBoxName);
    _presetsBox = await Hive.openBox<LabelPresetModel>(_presetsBoxName);
    _settingsBox = await Hive.openBox<PrintingSettingsModel>(_settingsBoxName);

    _initialized = true;
  }

  static Box<PrinterConfigModel> get printersBox {
    if (_printersBox == null) {
      throw StateError(
        'لم يتم تهيئة التخزين المحلي للطباعة. يرجى استدعاء initialize() أولاً.',
      );
    }
    return _printersBox!;
  }

  static Box<LabelPresetModel> get presetsBox {
    if (_presetsBox == null) {
      throw StateError(
        'لم يتم تهيئة التخزين المحلي للطباعة. يرجى استدعاء initialize() أولاً.',
      );
    }
    return _presetsBox!;
  }

  static Box<PrintingSettingsModel> get settingsBox {
    if (_settingsBox == null) {
      throw StateError(
        'لم يتم تهيئة التخزين المحلي للطباعة. يرجى استدعاء initialize() أولاً.',
      );
    }
    return _settingsBox!;
  }

  static PrintingSettingsModel getSettings() {
    return settingsBox.get(_settingsKey) ?? PrintingSettingsModel();
  }

  static Future<void> saveSettings(PrintingSettingsModel settings) async {
    await settingsBox.put(_settingsKey, settings);
  }

  static Future<void> close() async {
    await _printersBox?.close();
    await _presetsBox?.close();
    await _settingsBox?.close();
    _initialized = false;
  }
}
