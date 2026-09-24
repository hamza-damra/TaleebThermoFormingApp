import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_config.dart';
import 'package:taleeb_thermoforming/domain/repositories/preset_repository.dart';
import 'package:taleeb_thermoforming/domain/repositories/printer_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/printing_provider.dart';

class _FakePrinterRepository implements PrinterRepository {
  @override
  List<PrinterConfig> getAll() => const [];
  @override
  PrinterConfig? getById(String id) => null;
  @override
  PrinterConfig? getDefault() => null;
  @override
  Future<void> save(PrinterConfig printer) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> setDefault(String id) async {}
}

class _FakePresetRepository implements PresetRepository {
  @override
  List<LabelPreset> getAll() => const [];
  @override
  LabelPreset? getById(String id) => null;
  @override
  Future<LabelPreset> save(LabelPreset preset) async => preset;
  @override
  Future<void> delete(String id) async {}
}

void main() {
  const content = PalletLabelContent(
    palletId: 200,
    qrValue: '037000000200',
    productDisplayName: 'TL-7 B250 Black',
    actualQuantity: 200,
    packageUnitDisplayName: 'كيس',
    lineDisplay: 'A',
  );

  PrintingProvider provider() =>
      PrintingProvider(_FakePrinterRepository(), _FakePresetRepository());

  // `print` accepts only a mapper-built PalletLabelContent — the loose
  // top/bottom/side string parameters are gone, so no caller can assemble
  // label business content of its own. That is enforced by the analyzer; the
  // tests below cover the runtime behaviour around it.
  group('PrintingProvider label-content contract', () {
    test('retry without a prior print reports no stored label', () async {
      final result = await provider().retryPrint();

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'لا توجد قيمة للطباعة');
    });

    test('a print with no selected printer stores no label to retry', () async {
      final subject = provider();
      final result = await subject.print(labelContent: content);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'لم يتم اختيار طابعة');
      expect(
        subject.lastPrintedValue,
        isNull,
        reason: 'a rejected print must not seed retry with stale content',
      );
    });
  });
}
