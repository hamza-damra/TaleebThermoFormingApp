import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_config.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_language.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/printing/printer_client.dart';

/// End-to-end proof over the real socket path: mapper → renderer → bitmap →
/// TSPL/ZPL → wire. A loopback `ServerSocket` stands in for the printer and
/// captures the exact bytes each print path would send.
///
/// Same-length quantities (200 vs 250) are byte-identical here because the
/// headless test font draws every glyph as the same box; that discrimination
/// lives in `pallet_label_content_test.dart`, on the string this pipeline
/// draws. Discrimination *at the wire* is shown with 200 vs 1000.
void main() {
  const preset = LabelPreset(
    id: 'test',
    name: 'test',
    widthMm: 50,
    heightMm: 30,
    marginMm: 2,
  );

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

  const line = ProductionLine(id: 1, name: 'خط 1', code: 'L1', lineNumber: 1);
  const scannedValue = '037000000200';

  late ServerSocket server;
  late PrinterConfig printer;
  late StreamController<Uint8List> captured;
  late StreamIterator<Uint8List> jobs;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    captured = StreamController<Uint8List>();
    jobs = StreamIterator<Uint8List>(captured.stream);
    // One accept loop for the whole test — `ServerSocket` allows a single
    // listener, so each print job is queued for the caller to pick up.
    server.listen((socket) {
      final chunks = <int>[];
      socket.listen(
        chunks.addAll,
        onDone: () {
          if (!captured.isClosed) {
            captured.add(Uint8List.fromList(chunks));
          }
        },
      );
    });
    printer = PrinterConfig(
      id: 'sim',
      name: 'simulator',
      ip: server.address.address,
      port: server.port,
      language: PrinterLanguage.tspl,
      labelPresetId: preset.id,
      timeoutMs: 5000,
    );
  });

  tearDown(() async {
    await jobs.cancel();
    await captured.close();
    await server.close();
  });

  /// Sends [content] through the real client and returns the captured bytes.
  Future<Uint8List> wireBytes(
    PalletLabelContent content, {
    PrinterLanguage language = PrinterLanguage.tspl,
  }) async {
    await PrinterClient(
      printer.copyWith(language: language),
    ).print(content: content, preset: preset, copies: 1);

    final hasJob = await jobs.moveNext().timeout(const Duration(seconds: 20));
    expect(hasJob, isTrue, reason: 'the simulator must receive the print job');
    return jobs.current;
  }

  PalletCreateResponse createdPallet(int quantity) => PalletCreateResponse(
    palletId: 200,
    scannedValue: scannedValue,
    operator: const Operator(id: 1, name: 'محمد'),
    productType: product,
    productionLine: line,
    quantity: quantity,
    currentDestination: 'PRODUCTION_LINE',
    createdAt: DateTime.utc(2026, 9, 6),
    createdAtDisplay: '2026-09-06',
  );

  SessionPalletDetail sessionPallet(int quantity) => SessionPalletDetail(
    palletId: 200,
    scannedValue: scannedValue,
    serialNumber: '00000200',
    quantity: quantity,
    sourceType: 'PRODUCTION_LINE',
    createdAt: DateTime.utc(2026, 9, 6),
    createdAtDisplay: '2026-09-06',
  );

  final group_ = SessionProductTypeGroup(
    productTypeId: 11,
    productTypeName: product.name,
    productTypePrefix: '037',
    completedPalletCount: 1,
    pallets: [sessionPallet(200)],
  );

  PalletLabel resolvedLabel(int quantity) => PalletLabel(
    palletId: 200,
    scannedValue: scannedValue,
    productTypeId: 11,
    productTypeName: product.name,
    productTypePrefix: '037',
    // The product's standard pack size, deliberately different from the
    // pallet's own quantity — the original defect printed this instead.
    packageQuantity: 250,
    packageUnit: 'BAG',
    packageUnitDisplayName: 'كيس',
    quantity: quantity,
    productionLineId: 1,
    productionLineName: 'خط 1',
    operatorName: 'محمد',
    createdAt: DateTime.utc(2026, 9, 6),
    createdAtDisplay: '2026-09-06',
  );

  group('Every print path reaches the wire identically', () {
    test(
      'initial, session reprint and number reprint send the same bytes',
      () async {
        final initial = await wireBytes(
          PalletLabelContentMapper.fromCreatedPallet(
            createdPallet(200),
            lineNumber: 1,
          ),
        );
        final sessionReprint = await wireBytes(
          PalletLabelContentMapper.fromSessionPallet(
            pallet: sessionPallet(200),
            group: group_,
            productType: product,
            lineNumber: 1,
          ),
        );
        final numberReprint = await wireBytes(
          PalletLabelContentMapper.fromResolvedLabel(
            resolvedLabel(200),
            productType: product,
            lineNumber: line.lineNumber,
          ),
        );

        expect(initial, isNotEmpty);
        expect(sessionReprint, equals(initial));
        expect(numberReprint, equals(initial));
      },
    );

    test(
      'a repeated print of the same content is byte-identical (retry)',
      () async {
        final content = PalletLabelContentMapper.fromCreatedPallet(
          createdPallet(200),
          lineNumber: 1,
        );
        // `PrintingProvider.retryPrint` replays the stored content object, so a
        // retry is exactly this: the same content through the same client.
        expect(await wireBytes(content), equals(await wireBytes(content)));
      },
    );

    test(
      'a historical pallet reprints its own quantity, not the pack size',
      () async {
        // The label carries packageQuantity 250 alongside pallet quantity 200.
        // The reprint must reproduce a fresh print of 200 and must not follow
        // any other quantity — shown here against 1000, the nearest value the
        // headless font can tell apart at the wire.
        final historical = await wireBytes(
          PalletLabelContentMapper.fromResolvedLabel(
            resolvedLabel(200),
            productType: product,
            lineNumber: line.lineNumber,
          ),
        );
        final freshTwoHundred = await wireBytes(
          PalletLabelContentMapper.fromCreatedPallet(
            createdPallet(200),
            lineNumber: 1,
          ),
        );
        final freshThousand = await wireBytes(
          PalletLabelContentMapper.fromCreatedPallet(
            createdPallet(1000),
            lineNumber: 1,
          ),
        );

        expect(historical, equals(freshTwoHundred));
        expect(historical, isNot(equals(freshThousand)));
      },
    );

    test('the grinding marker reaches the wire identically from all three '
        'paths, on TSPL and ZPL', () async {
      const marker = '(موصى بالجرش)';
      final created = createdPallet(200);
      final markedCreate = PalletCreateResponse(
        palletId: created.palletId,
        scannedValue: created.scannedValue,
        operator: created.operator,
        productType: created.productType,
        productionLine: created.productionLine,
        quantity: created.quantity,
        currentDestination: created.currentDestination,
        createdAt: created.createdAt,
        createdAtDisplay: created.createdAtDisplay,
        grindingRecommended: true,
        grindingLabelText: marker,
        labelReprintAllowed: true,
      );
      final s = sessionPallet(200);
      final markedSession = SessionPalletDetail(
        palletId: s.palletId,
        scannedValue: s.scannedValue,
        serialNumber: s.serialNumber,
        quantity: s.quantity,
        sourceType: s.sourceType,
        createdAt: s.createdAt,
        createdAtDisplay: s.createdAtDisplay,
        grindingRecommended: true,
        grindingLabelText: marker,
        labelReprintAllowed: true,
        grindingStatus: 'PENDING_APPROVAL',
      );
      final r = resolvedLabel(200);
      final markedLabel = PalletLabel(
        palletId: r.palletId,
        scannedValue: r.scannedValue,
        productTypeId: r.productTypeId,
        productTypeName: r.productTypeName,
        productTypePrefix: r.productTypePrefix,
        packageQuantity: r.packageQuantity,
        packageUnit: r.packageUnit,
        packageUnitDisplayName: r.packageUnitDisplayName,
        quantity: r.quantity,
        productionLineId: r.productionLineId,
        productionLineName: r.productionLineName,
        operatorName: r.operatorName,
        createdAt: r.createdAt,
        createdAtDisplay: r.createdAtDisplay,
        grindingRecommended: true,
        grindingLabelText: marker,
        labelReprintAllowed: true,
      );

      for (final language in PrinterLanguage.values) {
        final plain = await wireBytes(
          PalletLabelContentMapper.fromCreatedPallet(created, lineNumber: 1),
          language: language,
        );
        final initial = await wireBytes(
          PalletLabelContentMapper.fromCreatedPallet(
            markedCreate,
            lineNumber: 1,
          ),
          language: language,
        );
        final session = await wireBytes(
          PalletLabelContentMapper.fromSessionPallet(
            pallet: markedSession,
            group: group_,
            productType: product,
            lineNumber: 1,
          ),
          language: language,
        );
        final byNumber = await wireBytes(
          PalletLabelContentMapper.fromResolvedLabel(
            markedLabel,
            productType: product,
            lineNumber: line.lineNumber,
          ),
          language: language,
        );

        expect(initial, isNot(equals(plain)), reason: '$language marker');
        expect(session, equals(initial), reason: '$language session');
        expect(byNumber, equals(initial), reason: '$language by number');
      }
    });

    test('ZPL path carries the same business content as TSPL', () async {
      final content = PalletLabelContentMapper.fromCreatedPallet(
        createdPallet(200),
        lineNumber: 1,
      );
      final zpl = await wireBytes(content, language: PrinterLanguage.zpl);
      final zplOther = await wireBytes(
        PalletLabelContentMapper.fromCreatedPallet(
          createdPallet(1000),
          lineNumber: 1,
        ),
        language: PrinterLanguage.zpl,
      );

      expect(String.fromCharCodes(zpl), startsWith('^XA'));
      expect(zpl, isNot(equals(zplOther)));
    });
  });
}
