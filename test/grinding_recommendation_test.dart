// Grinding recommendation at pallet creation + grinding label marker —
// docs/PALLETIZING_GRINDING_RECOMMENDATION_HANDOFF.md §12.
//
//   * the create request carries `grindingRecommendation` only when set,
//   * the three label paths carry the backend's marker / reprint flag,
//   * the label grows one bottom line for the marker and normal labels print
//     exactly as before,
//   * reprint is impossible once grinding started or finished,
//   * a `PALLET_GRINDING_CHANGED` frame refreshes an open drill-down.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/core/constants/grinding_recommendation_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/data/datasources/api_client.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/data/models/pallet_create_response_model.dart';
import 'package:taleeb_thermoforming/data/models/pallet_label_model.dart';
import 'package:taleeb_thermoforming/data/models/session_production_detail_model.dart';
import 'package:taleeb_thermoforming/data/repositories/palletizing_repository_impl.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizing_line.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_config.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/session_table_row.dart';
import 'package:taleeb_thermoforming/domain/repositories/preset_repository.dart';
import 'package:taleeb_thermoforming/domain/repositories/printer_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/providers/printing_provider.dart';
import 'package:taleeb_thermoforming/presentation/widgets/create_pallet_dialog.dart';
import 'package:taleeb_thermoforming/presentation/widgets/reprint_by_id_dialog.dart';
import 'package:taleeb_thermoforming/presentation/widgets/session_drilldown_dialog.dart';
import 'package:taleeb_thermoforming/printing/label_renderer.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

const _marker = '(موصى بالجرش)';
const _lineId = 11;

final _product = ProductType(
  id: 11,
  name: 'TL-7 B250 Black / أسود / 250 كيس',
  productName: 'TL-7 B250 Black',
  prefix: '037',
  color: 'أسود',
  packageQuantity: 250,
  packageUnit: 'BAG',
  packageUnitDisplayName: 'كيس',
);

/// One row of the handoff's marker table (§4.2), as the backend sends it.
class _MarkerState {
  final String name;
  final bool? recommended;
  final String? text;
  final bool? reprintAllowed;
  final String? expectedMarker;
  final bool expectedAllowed;

  const _MarkerState(
    this.name, {
    required this.recommended,
    required this.text,
    required this.reprintAllowed,
    required this.expectedMarker,
    required this.expectedAllowed,
  });
}

const _markerStates = [
  _MarkerState(
    'no order',
    recommended: false,
    text: null,
    reprintAllowed: true,
    expectedMarker: null,
    expectedAllowed: true,
  ),
  _MarkerState(
    'PENDING_APPROVAL',
    recommended: true,
    text: _marker,
    reprintAllowed: true,
    expectedMarker: _marker,
    expectedAllowed: true,
  ),
  _MarkerState(
    'READY_FOR_GRINDING',
    recommended: true,
    text: _marker,
    reprintAllowed: true,
    expectedMarker: _marker,
    expectedAllowed: true,
  ),
  _MarkerState(
    'REJECTED',
    recommended: false,
    text: null,
    reprintAllowed: true,
    expectedMarker: null,
    expectedAllowed: true,
  ),
  _MarkerState(
    'IN_GRINDING',
    recommended: false,
    text: null,
    reprintAllowed: false,
    expectedMarker: null,
    expectedAllowed: false,
  ),
  _MarkerState(
    'COMPLETED (recommended still true)',
    recommended: true,
    text: null,
    reprintAllowed: false,
    expectedMarker: null,
    expectedAllowed: false,
  ),
  _MarkerState(
    'older backend (fields absent)',
    recommended: null,
    text: null,
    reprintAllowed: null,
    expectedMarker: null,
    expectedAllowed: true,
  ),
];

PalletCreateResponse _created({
  bool? recommended,
  String? text,
  bool? reprintAllowed,
}) => PalletCreateResponse(
  palletId: 200,
  scannedValue: '037000000200',
  operator: const Operator(id: 1, name: 'محمد'),
  productType: _product,
  productionLine: const ProductionLine(
    id: _lineId,
    name: 'خط أ',
    code: 'L1',
    lineNumber: 1,
  ),
  quantity: 200,
  currentDestination: 'PRODUCTION_LINE',
  createdAt: DateTime.utc(2026, 9, 22),
  createdAtDisplay: '2026-09-22',
  grindingRecommended: recommended,
  grindingLabelText: text,
  labelReprintAllowed: reprintAllowed,
);

SessionPalletDetail _sessionPallet({
  int palletId = 200,
  bool? recommended,
  String? text,
  bool? reprintAllowed,
  String? status,
  String? statusLabel,
}) => SessionPalletDetail(
  palletId: palletId,
  scannedValue: '037${palletId.toString().padLeft(9, '0')}',
  serialNumber: palletId.toString().padLeft(9, '0'),
  quantity: 200,
  sourceType: 'PRODUCTION_LINE',
  createdAt: DateTime.utc(2026, 9, 22),
  createdAtDisplay: '2026-09-22',
  grindingRecommended: recommended,
  grindingLabelText: text,
  labelReprintAllowed: reprintAllowed,
  grindingStatus: status,
  grindingStatusLabel: statusLabel,
);

SessionProductTypeGroup _group(List<SessionPalletDetail> pallets) =>
    SessionProductTypeGroup(
      productTypeId: 11,
      productTypeName: _product.name,
      productTypePrefix: '037',
      completedPalletCount: pallets.length,
      pallets: pallets,
    );

PalletLabel _label({bool? recommended, String? text, bool? reprintAllowed}) =>
    PalletLabel(
      palletId: 200,
      scannedValue: '037000000200',
      productTypeId: 11,
      productTypeName: _product.name,
      productTypePrefix: '037',
      packageQuantity: 250,
      packageUnit: 'BAG',
      packageUnitDisplayName: 'كيس',
      quantity: 200,
      productionLineId: _lineId,
      productionLineName: 'خط أ',
      operatorName: 'محمد',
      createdAt: DateTime.utc(2026, 9, 22),
      createdAtDisplay: '2026-09-22',
      grindingRecommended: recommended,
      grindingLabelText: text,
      labelReprintAllowed: reprintAllowed,
    );

const _plain = PalletLabelContent(
  palletId: 200,
  qrValue: '037000000200',
  productDisplayName: 'TL-7 B250 Black',
  actualQuantity: 200,
  packageUnitDisplayName: 'كيس',
  lineDisplay: 'A',
);

const _marked = PalletLabelContent(
  palletId: 200,
  qrValue: '037000000200',
  productDisplayName: 'TL-7 B250 Black',
  actualQuantity: 200,
  packageUnitDisplayName: 'كيس',
  lineDisplay: 'A',
  grindingRecommended: true,
  grindingLabelText: _marker,
);

// ── HTTP fakes (repository serialisation) ──

class _DeviceKeyStorage extends AuthLocalStorage {
  @override
  Future<String?> getDeviceKey() async => 'test-device-key';

  @override
  Future<String?> getToken() async => null;
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Object? body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _createdJson({Map<String, dynamic> extra = const {}}) => {
  'palletId': 50412,
  'scannedValue': '120000004411',
  'operator': {'id': 14, 'name': 'عامل'},
  'productType': {
    'id': 12,
    'name': 'منتج',
    'productName': 'منتج',
    'prefix': '120',
    'color': '',
    'packageQuantity': 32,
    'packageUnit': 'BAG',
  },
  'productionLine': {'id': 1, 'name': 'خط أ', 'lineNumber': 1},
  'quantity': 32,
  'currentDestination': 'PRODUCTION',
  'createdAt': '2026-09-22T05:31:07.412Z',
  ...extra,
};

// ── Printing fakes ──

class _NoPrinters implements PrinterRepository {
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

class _NoPresets implements PresetRepository {
  @override
  List<LabelPreset> getAll() => const [];
  @override
  LabelPreset? getById(String id) => null;
  @override
  Future<LabelPreset> save(LabelPreset preset) async => preset;
  @override
  Future<void> delete(String id) async {}
}

/// Serves `fetchPalletLabel` on top of the shared fake.
class _LabelRepo extends FakePalletizingRepository {
  Future<PalletLabel> Function(String scannedValue)? labelFn;

  @override
  Future<PalletLabel> fetchPalletLabel(String scannedValue) {
    final fn = labelFn;
    if (fn == null) throw UnimplementedError('labelFn not configured');
    return fn(scannedValue);
  }
}

BootstrapLineState _line({List<SessionTableRow> rows = const []}) =>
    BootstrapLineState(
      lineId: _lineId,
      lineNumber: 1,
      lineName: 'خط أ',
      lineDisplayName: 'خط أ',
      isAuthorized: true,
      authorizedOperator: const Operator(id: 1, name: 'Operator 1'),
      lineUiMode: 'AUTHORIZED',
      currentPlanItemId: 912,
      currentPlanItemProductTypeId: 11,
      currentPlanItemProductName: _product.name,
      sessionTable: rows,
    );

const _rows = [
  SessionTableRow(
    productTypeId: 11,
    productTypeName: 'TL-7 B250 Black / أسود / 250 كيس',
    completedPalletCount: 1,
    completedPackageCount: 200,
    loosePackageCount: 0,
  ),
];

PalletizingAppSseEvent _frame(String id, String reason) =>
    PalletizingAppSseEvent(
      eventId: id,
      reason: reason,
      palletizingLineId: _lineId,
    );

void main() {
  group('Create request serialisation', () {
    Future<Map<String, dynamic>> sentBody({
      String? reason,
      int? faletQuantity,
    }) async {
      final client = ApiClient(authStorage: _DeviceKeyStorage());
      final adapter = _CannedAdapter(201, {
        'success': true,
        'data': _createdJson(),
      });
      client.dio.httpClientAdapter = adapter;
      await PalletizingRepositoryImpl(apiClient: client).createLinePallet(
        lineId: 1,
        productTypeId: 12,
        quantity: 32,
        expectedPlanItemId: 889,
        firstPalletFaletExpectedQuantity: faletQuantity,
        grindingRecommendationReason: reason,
      );
      return adapter.lastRequest!.data as Map<String, dynamic>;
    }

    test('a normal pallet sends no grindingRecommendation', () async {
      final body = await sentBody();
      expect(body.containsKey('grindingRecommendation'), isFalse);
      expect(body['expectedPlanItemId'], 889);
    });

    test('a recommended pallet sends the trimmed reason', () async {
      final body = await sentBody(reason: '  طباعة غير واضحة على الكاسات  ');
      expect(body['grindingRecommendation'], {
        'reason': 'طباعة غير واضحة على الكاسات',
      });
    });

    test('combines with the first-pallet FALET block', () async {
      final body = await sentBody(reason: 'تشوه', faletQuantity: 7);
      expect(body['grindingRecommendation'], {'reason': 'تشوه'});
      expect(
        (body['firstPalletFaletConsumption'] as Map)['expectedFaletQuantity'],
        7,
      );
    });
  });

  group('Response parsing', () {
    test('create response carries the PENDING order and the marker', () {
      final model = PalletCreateResponseModel.fromJson(
        _createdJson(
          extra: {
            'grindingOrder': {
              'id': 1043,
              'orderNumber': 'GR-001043',
              'status': 'PENDING_APPROVAL',
              'statusLabel': 'بانتظار موافقة المدير على توصية الجرش',
              'sourceType': 'PALLET',
              'sourceOrigin': 'PALLETIZING_PALLET',
              'creationBasis': 'LIVE',
              'managerApprovalRequired': true,
              'legacy': false,
            },
            'grindingRecommended': true,
            'grindingLabelText': _marker,
            'labelReprintAllowed': true,
          },
        ),
      );

      final order = model.grindingOrder!;
      expect(order.id, 1043);
      expect(order.orderNumber, 'GR-001043');
      expect(order.status, 'PENDING_APPROVAL');
      expect(order.statusLabel, 'بانتظار موافقة المدير على توصية الجرش');
      expect(order.sourceOrigin, 'PALLETIZING_PALLET');
      expect(order.managerApprovalRequired, isTrue);
      expect(order.legacy, isFalse);
      expect(model.grindingRecommended, isTrue);
      expect(model.grindingLabelText, _marker);
      expect(model.labelReprintAllowed, isTrue);
    });

    test('an older backend omits every grinding field', () {
      final model = PalletCreateResponseModel.fromJson(_createdJson());
      expect(model.grindingOrder, isNull);
      expect(model.grindingRecommended, isNull);
      expect(model.grindingLabelText, isNull);
      expect(model.labelReprintAllowed, isNull);
    });

    test('a malformed grindingOrder block is ignored, not fatal', () {
      final model = PalletCreateResponseModel.fromJson(
        _createdJson(
          extra: {
            'grindingOrder': {'orderNumber': 'GR-001043'},
            'grindingRecommended': true,
            'grindingLabelText': _marker,
          },
        ),
      );
      expect(model.grindingOrder, isNull);
      expect(model.grindingRecommended, isTrue);
    });

    test('reprint label payload parses the three fields', () {
      final model = PalletLabelModel.fromJson({
        'palletId': 200,
        'scannedValue': '037000000200',
        'productTypeName': 'منتج',
        'productTypePrefix': '037',
        'quantity': 200,
        'productionLineName': 'خط أ',
        'operatorName': 'محمد',
        'createdAt': '2026-09-22T05:40:00Z',
        'createdAtDisplay': '2026-09-22',
        'grindingRecommended': true,
        'grindingLabelText': _marker,
        'labelReprintAllowed': true,
      });
      expect(model.grindingRecommended, isTrue);
      expect(model.grindingLabelText, _marker);
      expect(model.labelReprintAllowed, isTrue);
    });

    test('session pallet parses the five fields; absent means allowed', () {
      final withOrder = SessionPalletDetailModel.fromJson(const {
        'palletId': 51,
        'scannedValue': '037000000051',
        'quantity': 12,
        'createdAt': '2026-09-22T08:00:00Z',
        'grindingRecommended': false,
        'labelReprintAllowed': false,
        'grindingStatus': 'IN_GRINDING',
        'grindingStatusLabel': 'قيد الجرش',
      });
      expect(withOrder.grindingStatus, 'IN_GRINDING');
      expect(withOrder.grindingStatusLabel, 'قيد الجرش');
      expect(withOrder.labelReprintAllowed, isFalse);
      expect(withOrder.isLabelReprintAllowed, isFalse);

      final old = SessionPalletDetailModel.fromJson(const {
        'palletId': 52,
        'scannedValue': '037000000052',
        'quantity': 12,
        'createdAt': '2026-09-22T08:00:00Z',
      });
      expect(old.grindingStatusLabel, isNull);
      expect(old.isLabelReprintAllowed, isTrue);
    });
  });

  group('Label builders × marker states (three print paths)', () {
    for (final s in _markerStates) {
      test(s.name, () {
        final paths = {
          'create': PalletLabelContentMapper.fromCreatedPallet(
            _created(
              recommended: s.recommended,
              text: s.text,
              reprintAllowed: s.reprintAllowed,
            ),
            lineNumber: 1,
          ),
          'session drill-down': PalletLabelContentMapper.fromSessionPallet(
            pallet: _sessionPallet(
              recommended: s.recommended,
              text: s.text,
              reprintAllowed: s.reprintAllowed,
            ),
            group: _group(const []),
            productType: _product,
            lineNumber: 1,
          ),
          'reprint by number': PalletLabelContentMapper.fromResolvedLabel(
            _label(
              recommended: s.recommended,
              text: s.text,
              reprintAllowed: s.reprintAllowed,
            ),
            productType: _product,
            lineNumber: 1,
          ),
        };
        for (final entry in paths.entries) {
          expect(
            entry.value.grindingMarkerText,
            s.expectedMarker,
            reason: '${entry.key} marker',
          );
          expect(
            entry.value.labelReprintAllowed,
            s.expectedAllowed,
            reason: '${entry.key} reprint flag',
          );
          // The QR / scanned value never changes with the marker.
          expect(entry.value.qrValue, '037000000200');
        }
      });
    }

    test('a stray text without grindingRecommended prints no marker', () {
      final content = PalletLabelContentMapper.fromResolvedLabel(
        _label(recommended: false, text: _marker),
      );
      expect(content.grindingMarkerText, isNull);
    });

    test('the retry copy keeps the marker (content equality includes it)', () {
      // PrintingProvider.retryPrint replays the stored content object, so the
      // marker must be part of the content's identity.
      expect(_marked, isNot(equals(_plain)));
      expect(
        _marked,
        equals(
          const PalletLabelContent(
            palletId: 200,
            qrValue: '037000000200',
            productDisplayName: 'TL-7 B250 Black',
            actualQuantity: 200,
            packageUnitDisplayName: 'كيس',
            lineDisplay: 'A',
            grindingRecommended: true,
            grindingLabelText: _marker,
          ),
        ),
      );
    });
  });

  group('Reason validation and Arabic text', () {
    test('required, trimmed, at most 500 characters', () {
      String? v(String s) => GrindingRecommendationStrings.validateReason(s);
      expect(v(''), 'سبب التوصية بالجرش مطلوب.');
      expect(v('   \n '), 'سبب التوصية بالجرش مطلوب.');
      expect(v('x' * 500), isNull);
      expect(v('  ${'x' * 500}  '), isNull);
      expect(v('x' * 501), 'يجب ألا يتجاوز السبب 500 حرف.');
    });

    test('PALLET_BLOCKED_BY_GRINDING maps to the handoff text', () {
      final e = ApiException(
        code: 'PALLET_BLOCKED_BY_GRINDING',
        message: 'English developer text',
        statusCode: 409,
      );
      expect(
        e.displayMessage,
        'الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق.',
      );
    });
  });

  group('Label layout with the marker line', () {
    const legacyIds = [
      'default_40x30',
      'default_50x25',
      'default_50x30',
      'default_60x40',
      'default_100x50',
    ];
    final presets = [
      ...DefaultPresets.all,
      for (final id in legacyIds) DefaultPresets.getById(id)!,
    ];

    test('normal labels keep their exact geometry', () {
      // QR sizes of the plain 4-side layout before the marker existed.
      const before = {
        'default_30x40': 86,
        'default_25x50': 46,
        'default_30x50': 86,
        'default_40x60': 150,
        'default_50x100': 214,
        'default_100x100': 613,
      };
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);
        expect(layout.hasMarkerLine, isFalse);
        expect(layout.qrSize, before[preset.id], reason: preset.name);
        expect(
          layout.bottomTextY,
          layout.heightDots - layout.marginDots - layout.mainFontHeight,
          reason: 'quantity stays the last line on ${preset.name}',
        );
      }
    });

    test('marker is the last line, below quantity, clear of the QR', () {
      for (final preset in presets) {
        final layout = LabelLayout.fromPreset(
          preset,
          hasText: true,
          hasMarkerLine: true,
        );
        final fh = layout.mainFontHeight;
        expect(layout.hasMarkerLine, isTrue);
        expect(
          layout.markerTextY + fh,
          lessThanOrEqualTo(layout.heightDots - layout.marginDots),
          reason: 'marker inside the printable area on ${preset.name}',
        );
        expect(
          layout.markerTextY,
          greaterThanOrEqualTo(layout.bottomTextY + fh),
          reason: 'marker below the quantity line on ${preset.name}',
        );
        expect(
          layout.bottomTextY,
          greaterThanOrEqualTo(layout.qrY + layout.qrSize),
          reason: 'quantity line below the QR on ${preset.name}',
        );
        expect(
          layout.qrY,
          greaterThanOrEqualTo(layout.topTextY + fh),
          reason: 'QR below the product line on ${preset.name}',
        );
        expect(layout.bottomTextY, greaterThanOrEqualTo(layout.sideBandBottom));
        expect(layout.qrSize, greaterThan(0), reason: preset.name);
      }
    });

    test('QR stays readable on every preset offered in the pickers', () {
      // Same floor as the plain-layout test. Legacy landscape stock (e.g.
      // 50×25 mm) is not offered any more; there the QR shrinks further.
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(
          preset,
          hasText: true,
          hasMarkerLine: true,
        );
        final minQrDots = preset.widthMm <= 30 ? 40 : 80;
        expect(
          layout.qrSize,
          greaterThanOrEqualTo(minQrDots),
          reason: 'QR stays readable on ${preset.name}',
        );
      }
    });

    test('current presets keep the product/quantity font size and, where '
        'width-bound, the QR size', () {
      for (final preset in DefaultPresets.all) {
        final plain = LabelLayout.fromPreset(preset, hasText: true);
        final marked = LabelLayout.fromPreset(
          preset,
          hasText: true,
          hasMarkerLine: true,
        );
        expect(
          marked.mainFontHeight,
          plain.mainFontHeight,
          reason: preset.name,
        );
        final plainZoneHeight = plain.sideBandBottom - plain.sideBandTop;
        if (plain.qrSize < plainZoneHeight) {
          expect(marked.qrSize, plain.qrSize, reason: preset.name);
        }
      }
    });
  });

  group('Label rendering', () {
    const preset = LabelPreset(
      id: 'test',
      name: 'test',
      widthMm: 50,
      heightMm: 100,
      marginMm: 4,
    );

    bool hasInk(LabelRenderResult r, int fromRow, int toRow) {
      for (var row = fromRow; row < toRow && row < r.height; row++) {
        for (var x = 0; x < r.widthBytes; x++) {
          if (r.monochromeBytes[row * r.widthBytes + x] != 0xFF) return true;
        }
      }
      return false;
    }

    test('the marker prints on its own line; quantity moves up', () async {
      final layout = LabelLayout.fromPreset(
        preset,
        hasText: true,
        hasMarkerLine: true,
      );
      final marked = await LabelRenderer().render(
        content: _marked,
        preset: preset,
      );
      final plain = await LabelRenderer().render(
        content: _plain,
        preset: preset,
      );

      final fh = layout.mainFontHeight;
      expect(
        hasInk(marked, layout.markerTextY, layout.markerTextY + fh),
        isTrue,
      );
      expect(
        hasInk(marked, layout.bottomTextY, layout.bottomTextY + fh),
        isTrue,
      );
      expect(marked.monochromeBytes, isNot(equals(plain.monochromeBytes)));
    });

    test('no marker text → byte-identical to a normal label', () async {
      final plain = await LabelRenderer().render(
        content: _plain,
        preset: preset,
      );
      final flaggedWithoutText = await LabelRenderer().render(
        content: const PalletLabelContent(
          palletId: 200,
          qrValue: '037000000200',
          productDisplayName: 'TL-7 B250 Black',
          actualQuantity: 200,
          packageUnitDisplayName: 'كيس',
          lineDisplay: 'A',
          grindingRecommended: true,
          grindingLabelText: '  ',
        ),
        preset: preset,
      );
      expect(flaggedWithoutText.monochromeBytes, equals(plain.monochromeBytes));
    });

    test('renders on every preset without error', () async {
      for (final p in DefaultPresets.all) {
        final result = await LabelRenderer().render(
          content: _marked,
          preset: p,
        );
        expect(result.monochromeBytes, isNotEmpty, reason: p.name);
      }
    });
  });

  group('Printing pipeline guard', () {
    test(
      'refuses a label whose grinding started, before anything else',
      () async {
        final printing = PrintingProvider(_NoPrinters(), _NoPresets());
        final result = await printing.print(
          labelContent: const PalletLabelContent(
            palletId: 200,
            qrValue: '037000000200',
            productDisplayName: 'TL-7 B250 Black',
            actualQuantity: 200,
            packageUnitDisplayName: 'كيس',
            lineDisplay: 'A',
            labelReprintAllowed: false,
          ),
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          GrindingRecommendationStrings.reprintBlocked,
        );
        expect(printing.lastPrintedValue, isNull, reason: 'no retry seeded');
      },
    );
  });

  group('Provider', () {
    test('createPallet forwards the reason to the repository', () async {
      final repo = FakePalletizingRepository();
      repo.bootstrapFn = () =>
          BootstrapResponse(productTypes: [_product], lines: [_line()]);
      repo.lineStateFn = (_) => _line();
      repo.createSuccessFn = (_) => _created(recommended: true, text: _marker);
      final provider = PalletizingProvider(
        repo,
        FakeAuthStorage(),
        FakeNotifications(),
      );
      await provider.loadBootstrap();

      await provider.createPallet(
        lineId: _lineId,
        productTypeId: 11,
        quantity: 200,
        expectedPlanItemId: 912,
        grindingRecommendationReason: 'تشوه الكاسات',
      );
      await provider.createPallet(
        lineId: _lineId,
        productTypeId: 11,
        quantity: 200,
        expectedPlanItemId: 912,
      );

      expect(repo.createCalls.map((c) => c.grindingRecommendationReason), [
        'تشوه الكاسات',
        null,
      ]);
    });

    Future<(FakePalletizingRepository, PalletizingProvider)> loaded() async {
      final repo = FakePalletizingRepository();
      repo.bootstrapFn = () => BootstrapResponse(
        productTypes: [_product],
        lines: [_line(rows: _rows)],
      );
      repo.lineStateFn = (_) => _line(rows: _rows);
      final provider = PalletizingProvider(
        repo,
        FakeAuthStorage(),
        FakeNotifications(),
      );
      await provider.loadBootstrap();
      return (repo, provider);
    }

    test('PALLET_GRINDING_CHANGED marks the session detail changed although '
        'the counts did not move', () async {
      final (_, provider) = await loaded();
      final before = provider.sessionDataRevision(_lineId);

      await provider.refreshFromSseEvents([_frame('a', 'PALLET_CREATED')]);
      expect(
        provider.sessionDataRevision(_lineId),
        before,
        reason: 'same counts, unrelated reason → no re-read',
      );

      await provider.refreshFromSseEvents([
        _frame('b', 'PALLET_GRINDING_CHANGED'),
      ]);
      expect(provider.sessionDataRevision(_lineId), before + 1);
    });

    test('…also when batched with a LINE_STATE_CHANGED bootstrap', () async {
      final (repo, provider) = await loaded();
      final before = provider.sessionDataRevision(_lineId);
      final bootstraps = repo.bootstrapCalls;

      await provider.refreshFromSseEvents([
        _frame('c', 'PALLET_GRINDING_CHANGED'),
        _frame('d', 'LINE_STATE_CHANGED'),
      ]);

      expect(repo.bootstrapCalls, bootstraps + 1);
      expect(provider.sessionDataRevision(_lineId), before + 1);
    });
  });

  group('Create pallet dialog', () {
    Future<List<Map<String, dynamic>?>> open(WidgetTester tester) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final results = <Map<String, dynamic>?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(
                    await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => CreatePalletDialog(
                        line: const PalletizingLine(
                          lineId: _lineId,
                          lineNumber: 1,
                        ),
                        initialProductType: _product,
                        initialQuantity: 200,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    final reasonField = find.byKey(const Key('grindingReasonField'));
    final grindingSwitch = find.byKey(
      const Key('grindingRecommendationSwitch'),
    );

    testWidgets('switch is off by default; a normal pallet sends no reason', (
      tester,
    ) async {
      final results = await open(tester);
      expect(find.text('توصية بالجرش'), findsOneWidget);
      expect(reasonField, findsNothing);

      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(results, [
        {'quantity': 200},
      ]);
    });

    testWidgets('switch reveals the required reason; empty → inline error, '
        'nothing sent', (tester) async {
      final results = await open(tester);
      await tester.tap(grindingSwitch);
      await tester.pumpAndSettle();
      expect(reasonField, findsOneWidget);
      expect(find.text('سبب التوصية بالجرش'), findsOneWidget);

      await tester.enterText(reasonField, '   ');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      expect(find.text('سبب التوصية بالجرش مطلوب.'), findsOneWidget);
      expect(results, isEmpty, reason: 'the dialog stays open');
      expect(find.byType(CreatePalletDialog), findsOneWidget);
    });

    testWidgets('a valid reason is returned trimmed', (tester) async {
      final results = await open(tester);
      await tester.tap(grindingSwitch);
      await tester.pumpAndSettle();
      await tester.enterText(reasonField, '  طباعة غير واضحة  ');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      expect(results, [
        {'quantity': 200, 'grindingReason': 'طباعة غير واضحة'},
      ]);
    });

    testWidgets('switching off again sends a normal pallet', (tester) async {
      final results = await open(tester);
      await tester.tap(grindingSwitch);
      await tester.pumpAndSettle();
      await tester.enterText(reasonField, 'سبب');
      await tester.tap(grindingSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      expect(results, [
        {'quantity': 200},
      ]);
    });
  });

  group('Session drill-down', () {
    const line = PalletizingLine(lineId: _lineId, lineNumber: 1);

    late List<SessionPalletDetail> pallets;

    Future<PalletizingProvider> open(WidgetTester tester) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = FakePalletizingRepository();
      repo.bootstrapFn = () => BootstrapResponse(
        productTypes: [_product],
        lines: [_line(rows: _rows)],
      );
      repo.lineStateFn = (_) => _line(rows: _rows);
      repo.sessionDetailFn = (_) async => SessionProductionDetail(
        lineId: _lineId,
        authorizationId: 900,
        groups: [_group(pallets)],
      );
      final provider = PalletizingProvider(
        repo,
        FakeAuthStorage(),
        FakeNotifications(),
      );
      await provider.loadBootstrap();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PalletizingProvider>.value(value: provider),
            ChangeNotifierProvider<PrintingProvider>(
              create: (_) => PrintingProvider(_NoPrinters(), _NoPresets()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      SessionDrilldownDialog.show(context: context, line: line),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return provider;
    }

    final printButton = find.byKey(const Key('sessionReprintPrintButton'));
    final blockedBanner = find.byKey(
      const Key('reprintBlockedByGrindingBanner'),
    );

    bool enabled(WidgetTester tester) =>
        tester.widget<ElevatedButton>(printButton).onPressed != null;

    testWidgets('row shows the grinding status chip when present', (
      tester,
    ) async {
      pallets = [
        _sessionPallet(
          palletId: 51,
          recommended: true,
          text: _marker,
          reprintAllowed: true,
          status: 'PENDING_APPROVAL',
          statusLabel: 'بانتظار موافقة المدير على توصية الجرش',
        ),
        _sessionPallet(palletId: 52),
      ];
      await open(tester);

      expect(find.byKey(const Key('grindingStatusChip-51')), findsOneWidget);
      expect(
        find.text('بانتظار موافقة المدير على توصية الجرش'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('grindingStatusChip-52')), findsNothing);
    });

    testWidgets('reprint is disabled with the handoff text once grinding '
        'started', (tester) async {
      pallets = [
        _sessionPallet(
          palletId: 51,
          reprintAllowed: false,
          status: 'IN_GRINDING',
          statusLabel: 'قيد الجرش',
        ),
      ];
      await open(tester);

      await tester.tap(find.byKey(const Key('reprintPallet-51')));
      await tester.pumpAndSettle();

      expect(blockedBanner, findsOneWidget);
      expect(
        find.text(
          'الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق.',
        ),
        findsOneWidget,
      );
      expect(enabled(tester), isFalse);
    });

    testWidgets('an open reprint dialog follows a grinding change', (
      tester,
    ) async {
      pallets = [
        _sessionPallet(
          palletId: 51,
          recommended: true,
          text: _marker,
          reprintAllowed: true,
          status: 'READY_FOR_GRINDING',
          statusLabel: 'جاهزة للجرش',
        ),
      ];
      final provider = await open(tester);
      await tester.tap(find.byKey(const Key('reprintPallet-51')));
      await tester.pumpAndSettle();
      expect(enabled(tester), isTrue);
      expect(blockedBanner, findsNothing);

      // The grinding worker starts grinding; the backend sends the frame.
      pallets = [
        _sessionPallet(
          palletId: 51,
          reprintAllowed: false,
          status: 'IN_GRINDING',
          statusLabel: 'قيد الجرش',
        ),
      ];
      await provider.refreshFromSseEvents([
        _frame('g1', 'PALLET_GRINDING_CHANGED'),
      ]);
      await tester.pumpAndSettle();

      expect(blockedBanner, findsOneWidget);
      expect(enabled(tester), isFalse);
    });
  });

  group('Reprint by number', () {
    Future<void> open(WidgetTester tester, _LabelRepo repo) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      repo.bootstrapFn = () =>
          BootstrapResponse(productTypes: [_product], lines: [_line()]);
      repo.lineStateFn = (_) => _line();
      final provider = PalletizingProvider(
        repo,
        FakeAuthStorage(),
        FakeNotifications(),
      );
      await provider.loadBootstrap();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PalletizingProvider>.value(value: provider),
            ChangeNotifierProvider<PrintingProvider>(
              create: (_) => PrintingProvider(_NoPrinters(), _NoPresets()),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ReprintByIdDialog())),
        ),
      );
      await tester.enterText(find.byType(TextField), '037000000200');
      await tester.tap(find.text('بحث'));
      await tester.pumpAndSettle();
    }

    final printButton = find.byKey(const Key('reprintByIdPrintButton'));

    testWidgets('a pending recommendation shows the marker; reprint enabled', (
      tester,
    ) async {
      final repo = _LabelRepo()
        ..labelFn = (_) async =>
            _label(recommended: true, text: _marker, reprintAllowed: true);
      await open(tester, repo);

      expect(find.text(_marker), findsOneWidget);
      expect(tester.widget<ElevatedButton>(printButton).onPressed, isNotNull);
      expect(
        find.byKey(const Key('reprintBlockedByGrindingBanner')),
        findsNothing,
      );
    });

    testWidgets('labelReprintAllowed=false disables reprint with the text', (
      tester,
    ) async {
      final repo = _LabelRepo()
        ..labelFn = (_) async => _label(reprintAllowed: false);
      await open(tester, repo);

      expect(
        find.byKey(const Key('reprintBlockedByGrindingBanner')),
        findsOneWidget,
      );
      expect(tester.widget<ElevatedButton>(printButton).onPressed, isNull);
    });

    testWidgets('409 PALLET_BLOCKED_BY_GRINDING → refusal dialog', (
      tester,
    ) async {
      final repo = _LabelRepo()
        ..labelFn = (_) async => throw ApiException(
          code: 'PALLET_BLOCKED_BY_GRINDING',
          message: 'Pallet is being ground',
          statusCode: 409,
        );
      await open(tester, repo);

      expect(find.text('تعذّرت إعادة الطباعة'), findsOneWidget);
      expect(
        find.text(
          'الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();
      expect(printButton, findsNothing, reason: 'back to a fresh search');
    });
  });
}
