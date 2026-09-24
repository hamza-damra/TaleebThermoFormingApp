import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';

void main() {
  final product = ProductType(
    id: 11,
    name: 'TL-7 B250 Black / أسود / 250 كيس',
    productName: 'TL-7 B250 Black',
    prefix: '037',
    color: 'أسود',
    packageQuantity: 250,
    packageUnit: 'BAG',
    packageUnitDisplayName: 'كيس',
    description: 'مواصفات المنتج (250- كيس)',
  );

  PalletCreateResponse created({required int id, required int quantity}) {
    return PalletCreateResponse(
      palletId: id,
      scannedValue: '037${id.toString().padLeft(9, '0')}',
      operator: const Operator(id: 1, name: 'محمد'),
      productType: product,
      productionLine: const ProductionLine(
        id: 1,
        name: 'خط 1',
        code: 'L1',
        lineNumber: 1,
      ),
      quantity: quantity,
      currentDestination: 'PRODUCTION_LINE',
      createdAt: DateTime.utc(2026, 9, 6),
      createdAtDisplay: '2026-09-06',
    );
  }

  group('PalletLabelContentMapper', () {
    test('uses actual pallet quantity, never product packageQuantity', () {
      final a = PalletLabelContentMapper.fromCreatedPallet(
        created(id: 200, quantity: 200),
        lineNumber: 1,
      );
      final b = PalletLabelContentMapper.fromCreatedPallet(
        created(id: 250, quantity: 250),
        lineNumber: 1,
      );

      expect(product.packageQuantity, 250);
      expect(a.actualQuantity, 200);
      expect(a.actualQuantityText, 'عدد العبوات: 200 كيس');
      expect(b.actualQuantity, 250);
      expect(b.actualQuantityText, 'عدد العبوات: 250 كيس');
    });

    test('session reprint uses SessionPalletDetail.quantity', () {
      final pallet = SessionPalletDetail(
        palletId: 200,
        scannedValue: '037000000200',
        serialNumber: '00000200',
        quantity: 200,
        sourceType: 'PRODUCTION_LINE',
        createdAt: DateTime.utc(2026, 9, 6),
        createdAtDisplay: '2026-09-06',
      );
      final group = SessionProductTypeGroup(
        productTypeId: 11,
        productTypeName: 'TL-7 B250 Black / أسود / 250 كيس',
        productTypePrefix: '037',
        completedPalletCount: 1,
        pallets: [pallet],
      );

      final content = PalletLabelContentMapper.fromSessionPallet(
        pallet: pallet,
        group: group,
        productType: product,
        lineNumber: 1,
      );

      expect(content.actualQuantity, 200);
      expect(content.packageUnitDisplayName, 'كيس');
    });

    test('reprint-by-number uses PalletLabel.quantity and structured unit', () {
      final label = PalletLabel(
        palletId: 200,
        scannedValue: '037000000200',
        productTypeId: 11,
        productTypeName: product.name,
        productTypePrefix: '037',
        packageQuantity: 250,
        packageUnit: 'BAG',
        packageUnitDisplayName: 'كيس',
        quantity: 200,
        productionLineId: 1,
        productionLineName: 'خط 1',
        operatorName: 'محمد',
        createdAt: DateTime.utc(2026, 9, 6),
        createdAtDisplay: '2026-09-06',
      );

      final content = PalletLabelContentMapper.fromResolvedLabel(label);
      expect(content.actualQuantity, 200);
      expect(content.actualQuantity, isNot(label.packageQuantity));
      expect(content.packageUnitDisplayName, 'كيس');
    });

    test('initial and both reprint mappings preserve critical content', () {
      final initial = PalletLabelContentMapper.fromCreatedPallet(
        created(id: 200, quantity: 200),
        lineNumber: 1,
      );
      final sessionPallet = SessionPalletDetail(
        palletId: 200,
        scannedValue: '037000000200',
        serialNumber: '00000200',
        quantity: 200,
        sourceType: 'PRODUCTION_LINE',
        createdAt: DateTime.utc(2026, 9, 6),
        createdAtDisplay: '2026-09-06',
      );
      final group = SessionProductTypeGroup(
        productTypeId: 11,
        productTypeName: 'TL-7 B250 Black / أسود / 250 كيس',
        productTypePrefix: '037',
        completedPalletCount: 1,
        pallets: [sessionPallet],
      );
      final session = PalletLabelContentMapper.fromSessionPallet(
        pallet: sessionPallet,
        group: group,
        productType: product,
        lineNumber: 1,
      );
      final resolved = PalletLabelContentMapper.fromResolvedLabel(
        PalletLabel(
          palletId: 200,
          scannedValue: '037000000200',
          productTypeId: 11,
          productTypeName: product.name,
          productTypePrefix: '037',
          packageQuantity: 250,
          packageUnit: 'BAG',
          packageUnitDisplayName: 'كيس',
          quantity: 200,
          productionLineId: 1,
          productionLineName: 'خط 1',
          operatorName: 'محمد',
          createdAt: DateTime.utc(2026, 9, 6),
          createdAtDisplay: '2026-09-06',
        ),
        productType: product,
        lineNumber: 1,
      );

      for (final reprint in [session, resolved]) {
        expect(reprint.palletId, initial.palletId);
        expect(reprint.qrValue, initial.qrValue);
        expect(reprint.productDisplayName, initial.productDisplayName);
        expect(reprint.actualQuantity, initial.actualQuantity);
        expect(reprint.packageUnitDisplayName, initial.packageUnitDisplayName);
        // Rendered bands, not just raw fields — the side band is the part a
        // worker reads off the pallet, so it must match the original print.
        expect(reprint.productText, initial.productText);
        expect(reprint.actualQuantityText, initial.actualQuantityText);
        expect(reprint.lineDisplay, initial.lineDisplay);
        expect(reprint.sideText, initial.sideText);
      }
    });

    test('reprint-by-number side band uses the line letter, not the long line '
        'name', () {
      final label = PalletLabel(
        palletId: 200,
        scannedValue: '037000000200',
        productTypeId: 11,
        productTypeName: product.name,
        productTypePrefix: '037',
        packageQuantity: 250,
        packageUnit: 'BAG',
        packageUnitDisplayName: 'كيس',
        quantity: 200,
        productionLineId: 1,
        productionLineName: 'خط الإنتاج الأول',
        operatorName: 'محمد',
        createdAt: DateTime.utc(2026, 9, 6),
        createdAtDisplay: '2026-09-06',
      );

      final resolved = PalletLabelContentMapper.fromResolvedLabel(
        label,
        productType: product,
        lineNumber: 1,
      );
      expect(resolved.lineDisplay, 'A');
      expect(resolved.sideText, '037000000200 (A)');

      final lineTwo = PalletLabelContentMapper.fromResolvedLabel(
        label,
        productType: product,
        lineNumber: 2,
      );
      expect(lineTwo.lineDisplay, 'B');

      // LINE_3 'خط ج' prints 'C' — never the old two-way 'B' fallback.
      final lineThree = PalletLabelContentMapper.fromResolvedLabel(
        label,
        productType: product,
        lineNumber: 3,
      );
      expect(lineThree.lineDisplay, 'C');
      expect(lineThree.sideText, '037000000200 (C)');
    });

    test(
      'side band falls back to the snapshot name when the line row is gone',
      () {
        final resolved = PalletLabelContentMapper.fromResolvedLabel(
          PalletLabel(
            palletId: 200,
            scannedValue: '037000000200',
            productTypeName: product.name,
            productTypePrefix: '037',
            quantity: 200,
            productionLineName: 'خط الإنتاج الأول',
            operatorName: 'محمد',
            createdAt: DateTime.utc(2026, 9, 6),
            createdAtDisplay: '2026-09-06',
          ),
        );
        expect(resolved.lineDisplay, 'خط الإنتاج الأول');
      },
    );

    test('missing structured unit never parses one from product text', () {
      final content = PalletLabelContentMapper.fromResolvedLabel(
        PalletLabel(
          palletId: 200,
          scannedValue: '037000000200',
          productTypeName: 'Product / 250 كيس',
          productTypePrefix: '037',
          quantity: 200,
          productionLineName: 'خط 1',
          operatorName: 'محمد',
          createdAt: DateTime.utc(2026, 9, 6),
          createdAtDisplay: '2026-09-06',
        ),
      );

      expect(content.packageUnitDisplayName, isNull);
      expect(content.actualQuantityText, 'عدد العبوات: 200');
    });
  });
}
