// Canonical product label: every surface shows the structured product name
// ("TT-4 B600 Yellow"), never the backend's composite
// `productName / color / packageQuantity unit`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/data/models/product_type_model.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizing_line.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/session_table_row.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/widgets/line_context_strip.dart';
import 'package:taleeb_thermoforming/presentation/widgets/session_table_widget.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

ProductType _catalogProduct({
  required int id,
  required String productName,
  required String color,
  int packageQuantity = 12,
  String unit = 'كيس',
}) => ProductTypeModel(
  id: id,
  // Exactly what the backend stores: ProductType.computeDisplayName().
  name: '$productName / $color / $packageQuantity $unit',
  productName: productName,
  prefix: id.toString().padLeft(3, '0'),
  color: color,
  packageQuantity: packageQuantity,
  packageUnit: unit == 'كيس' ? 'BAG' : 'CARTON',
  packageUnitDisplayName: unit,
);

const _lineId = 11;

BootstrapLineState _line({
  int? planProductId,
  String? planProductName,
  List<SessionTableRow> rows = const [],
}) => BootstrapLineState(
  lineId: _lineId,
  lineNumber: 1,
  lineName: 'خط أ',
  lineDisplayName: 'خط أ',
  isAuthorized: true,
  authorizedOperator: const Operator(id: 1, name: 'Operator 1'),
  lineUiMode: 'AUTHORIZED',
  currentPlanItemId: planProductId == null ? null : 912,
  currentPlanItemProductTypeId: planProductId,
  currentPlanItemProductName: planProductName,
  sessionTable: rows,
);

Future<PalletizingProvider> _loadedProvider({
  required List<ProductType> catalog,
  required BootstrapLineState line,
}) async {
  final repo = FakePalletizingRepository()
    ..bootstrapFn = () =>
        BootstrapResponse(productTypes: catalog, lines: [line]);
  final provider = PalletizingProvider(
    repo,
    FakeAuthStorage(),
    FakeNotifications(),
  );
  await provider.loadBootstrap();
  return provider;
}

void main() {
  group('ProductType.resolveDisplayName', () {
    test('prefers the structured productName over the composite name', () {
      final yellow = _catalogProduct(
        id: 4,
        productName: 'TT-4 B600 Yellow',
        color: 'Yellow',
      );
      expect(yellow.name, 'TT-4 B600 Yellow / Yellow / 12 كيس');
      expect(yellow.displayName, 'TT-4 B600 Yellow');
      expect(
        ProductType.resolveDisplayName(
          productType: yellow,
          backendName: 'TT-4 B600 Yellow / Yellow / 12 كيس',
        ),
        'TT-4 B600 Yellow',
      );
    });

    test('reduces a composite with no catalog entry, for any colour/unit', () {
      const cases = {
        'TT-4 B600 Yellow / Yellow / 12 كيس': 'TT-4 B600 Yellow',
        'TT-4 B600 Blue / Blue / 12 كيس': 'TT-4 B600 Blue',
        'TBS-13 C1500 Beige / Beige / 32 كرتونة': 'TBS-13 C1500 Beige',
        'TL-7 B250 Black / أسود / 250 كيس': 'TL-7 B250 Black',
        'لنش بوكس مقطع / أبيض / 500 كرتونة': 'لنش بوكس مقطع',
      };
      cases.forEach((composite, expected) {
        expect(
          ProductType.resolveDisplayName(backendName: composite),
          expected,
          reason: composite,
        );
      });
    });

    test('keeps separators that belong to the product name itself', () {
      // Only the two segments the backend appends are removed.
      expect(
        ProductType.resolveDisplayName(
          backendName: 'Lid / Cap 90 / Clear / 24 كرتونة',
        ),
        'Lid / Cap 90',
      );
      expect(
        ProductType.resolveDisplayName(backendName: 'Cup 1/2 L / Red / 50 كيس'),
        'Cup 1/2 L',
      );
    });

    test('never truncates a name that is not a backend composite', () {
      const plain = [
        'TT-4 B600 Yellow',
        'Cup 1/2 L',
        'A / B',
        'Box 10 / 20',
        'Tray A / B / 20',
        'Product / 250 كيس',
        'Plan Product 25',
      ];
      for (final name in plain) {
        expect(
          ProductType.resolveDisplayName(backendName: name),
          name,
          reason: name,
        );
      }
    });

    test('a catalog entry with a blank productName falls back to the name', () {
      final legacy = ProductTypeModel(
        id: 9,
        name: 'TT-9 Green / Green / 10 كيس',
        productName: '  ',
        prefix: '009',
        color: 'Green',
        packageQuantity: 10,
        packageUnit: 'BAG',
        packageUnitDisplayName: 'كيس',
      );
      expect(legacy.displayName, 'TT-9 Green');
    });

    test('null / blank input yields an empty label, never a crash', () {
      expect(ProductType.resolveDisplayName(), '');
      expect(ProductType.resolveDisplayName(backendName: '   '), '');
      expect(ProductType.productNameFromComposite(' / X / 1 كيس'), isNull);
    });
  });

  group('PalletizingProvider product labels', () {
    final yellow = _catalogProduct(
      id: 4,
      productName: 'TT-4 B600 Yellow',
      color: 'Yellow',
    );
    final blue = _catalogProduct(
      id: 5,
      productName: 'TT-4 B600 Blue',
      color: 'Blue',
    );

    test('current plan-item product uses the catalog productName', () async {
      final provider = await _loadedProvider(
        catalog: [yellow, blue],
        line: _line(planProductId: 5, planProductName: blue.name),
      );

      expect(provider.getCurrentPlanItemProductName(_lineId), 'TT-4 B600 Blue');
      expect(
        provider.getCurrentPlanItemProductType(_lineId)?.productName,
        'TT-4 B600 Blue',
      );
    });

    test('a plan product missing from the catalog is still shown '
        'without the composite suffix', () async {
      final provider = await _loadedProvider(
        catalog: [yellow],
        line: _line(
          planProductId: 77,
          planProductName: 'TT-7 C900 Red / Red / 20 كرتونة',
        ),
      );

      expect(provider.getCurrentPlanItemProductName(_lineId), 'TT-7 C900 Red');
      final fallback = provider.getCurrentPlanItemProductType(_lineId)!;
      expect(fallback.id, 77);
      expect(fallback.productName, 'TT-7 C900 Red');
    });

    test('no plan item → no product label', () async {
      final provider = await _loadedProvider(catalog: [yellow], line: _line());
      expect(provider.getCurrentPlanItemProductName(_lineId), isNull);
    });

    test('productDisplayName resolves rows by productTypeId', () async {
      final provider = await _loadedProvider(catalog: [yellow], line: _line());

      expect(
        provider.productDisplayName(productTypeId: 4, backendName: yellow.name),
        'TT-4 B600 Yellow',
      );
      // Unknown id → reduced snapshot name.
      expect(
        provider.productDisplayName(
          productTypeId: 404,
          backendName: 'TT-4 B600 Blue / Blue / 12 كيس',
        ),
        'TT-4 B600 Blue',
      );
      expect(provider.productTypeById(null), isNull);
    });
  });

  group('Label content', () {
    test('a session reprint without a catalog entry prints the product name '
        'only', () {
      final pallet = SessionPalletDetail(
        palletId: 51,
        scannedValue: '004000000051',
        serialNumber: '000000051',
        quantity: 12,
        sourceType: 'PRODUCTION_LINE',
        createdAt: DateTime.utc(2026, 9, 16),
        createdAtDisplay: '2026-09-16',
      );
      final content = PalletLabelContentMapper.fromSessionPallet(
        pallet: pallet,
        group: SessionProductTypeGroup(
          productTypeId: 4,
          productTypeName: 'TT-4 B600 Yellow / Yellow / 12 كيس',
          productTypePrefix: '004',
          completedPalletCount: 1,
          pallets: [pallet],
        ),
        productType: null,
        lineNumber: 1,
      );
      expect(content.productDisplayName, 'TT-4 B600 Yellow');
    });
  });

  group('Widgets', () {
    Future<PalletizingProvider> pump(
      WidgetTester tester,
      Widget Function(PalletizingProvider provider) child,
      PalletizingProvider provider,
    ) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<PalletizingProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: child(provider))),
          ),
        ),
      );
      await tester.pump();
      return provider;
    }

    const line = PalletizingLine(lineId: _lineId, lineNumber: 1);

    testWidgets('current product card shows only the product name', (
      tester,
    ) async {
      final yellow = _catalogProduct(
        id: 4,
        productName: 'TT-4 B600 Yellow',
        color: 'Yellow',
      );
      final provider = await tester.runAsync(
        () => _loadedProvider(
          catalog: [yellow],
          line: _line(planProductId: 4, planProductName: yellow.name),
        ),
      );
      await pump(tester, (_) => const LineContextStrip(line: line), provider!);

      expect(find.text('TT-4 B600 Yellow'), findsOneWidget);
      expect(find.textContaining('/ Yellow /'), findsNothing);
      expect(find.textContaining('12 كيس'), findsNothing);
    });

    testWidgets('shift summary rows show only the product name', (
      tester,
    ) async {
      final provider = await tester.runAsync(
        () => _loadedProvider(
          catalog: const [],
          line: _line(
            rows: const [
              SessionTableRow(
                productTypeId: 5,
                productTypeName: 'TT-4 B600 Blue / Blue / 12 كيس',
                completedPalletCount: 3,
                completedPackageCount: 36,
                loosePackageCount: 0,
              ),
            ],
          ),
        ),
      );
      await pump(
        tester,
        (p) => SessionTableWidget(line: line, rows: p.getSessionTable(_lineId)),
        provider!,
      );

      expect(find.text('TT-4 B600 Blue'), findsOneWidget);
      expect(find.textContaining('/ Blue /'), findsNothing);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
    });
  });
}
