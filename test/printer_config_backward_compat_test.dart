import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/core/constants/printing_constants.dart';
import 'package:taleeb_thermoforming/data/models/printer_config_model.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_config.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_language.dart';

void main() {
  group('PrinterConfigModel ↔ PrinterConfig backward compatibility', () {
    test('legacy row without language defaults to TSPL', () {
      final legacy = PrinterConfigModel(
        id: 'p1',
        name: 'XPrinter',
        ip: '192.168.1.10',
        port: 9100,
        isDefault: true,
        timeoutMs: 3000,
        // language and labelPresetId omitted — simulates pre-feature rows.
      );

      final entity = legacy.toEntity();

      expect(entity.language, PrinterLanguage.tspl);
    });

    test('legacy row without labelPresetId defaults to PrintingConstants default', () {
      final legacy = PrinterConfigModel(
        id: 'p1',
        name: 'XPrinter',
        ip: '192.168.1.10',
        port: 9100,
        isDefault: true,
        timeoutMs: 3000,
      );

      final entity = legacy.toEntity();

      expect(entity.labelPresetId, PrintingConstants.defaultPresetId);
    });

    test('new row with language=zpl round-trips correctly', () {
      final entity = const PrinterConfig(
        id: 'z1',
        name: 'Zebra ZD230t',
        ip: '192.168.1.20',
        port: 9100,
        language: PrinterLanguage.zpl,
        labelPresetId: 'default_50x30',
      );

      final model = PrinterConfigModel.fromEntity(entity);
      final restored = model.toEntity();

      expect(model.language, 'zpl');
      expect(restored.language, PrinterLanguage.zpl);
      expect(restored.labelPresetId, 'default_50x30');
    });

    test('new row with language=tspl round-trips correctly', () {
      final entity = const PrinterConfig(
        id: 'x1',
        name: 'XPrinter XP-410B',
        ip: '192.168.1.10',
        port: 9100,
        language: PrinterLanguage.tspl,
        labelPresetId: 'default_40x30',
      );

      final model = PrinterConfigModel.fromEntity(entity);
      final restored = model.toEntity();

      expect(model.language, 'tspl');
      expect(restored.language, PrinterLanguage.tspl);
      expect(restored.labelPresetId, 'default_40x30');
    });

    test('unknown language string falls back to TSPL', () {
      expect(PrinterLanguage.fromWireValue(null), PrinterLanguage.tspl);
      expect(PrinterLanguage.fromWireValue('bogus'), PrinterLanguage.tspl);
      expect(PrinterLanguage.fromWireValue('tspl'), PrinterLanguage.tspl);
      expect(PrinterLanguage.fromWireValue('zpl'), PrinterLanguage.zpl);
    });

    test('PrinterConfig has TSPL + default preset as defaults', () {
      final fresh = const PrinterConfig(id: 'x', name: 'n', ip: '1.1.1.1');

      expect(fresh.language, PrinterLanguage.tspl);
      expect(fresh.labelPresetId, PrintingConstants.defaultPresetId);
    });
  });
}
