// "ملخص المناوبة" stays equal to the backend after every pallet mutation, and
// "تفاصيل إنتاج المناوبة" shows the same session with full pallet numbers.
//
// The fake repository plays the backend: each test mutates `_Backend` the way
// a create / quantity edit / cancellation commits, then delivers the refresh
// trigger the app would get (the create response, or an SSE frame). The app
// never adjusts a counter itself — every value asserted here comes from a
// backend read.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/data/models/product_type_model.dart';
import 'package:taleeb_thermoforming/data/models/session_production_detail_model.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/operator.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_create_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizing_line.dart';
import 'package:taleeb_thermoforming/domain/entities/product_type.dart';
import 'package:taleeb_thermoforming/domain/entities/production_line.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/entities/session_table_row.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/widgets/session_drilldown_dialog.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

const _lineId = 11;
const _productId = 4;
const _composite = 'TT-4 B600 Yellow / Yellow / 12 كيس';

final ProductType _yellow = ProductTypeModel(
  id: _productId,
  name: _composite,
  productName: 'TT-4 B600 Yellow',
  prefix: '004',
  color: 'Yellow',
  packageQuantity: 12,
  packageUnit: 'BAG',
  packageUnitDisplayName: 'كيس',
);

/// The backend's committed state for one open session on line 11.
class _Backend {
  /// Pallet quantities of the ACTIVE pallets, oldest first. Serials are
  /// assigned from the backend's counter and never reused.
  final List<({int serial, int quantity})> pallets = [];
  int _lastSerial = 50;

  _Backend(List<int> quantities) {
    quantities.forEach(add);
  }

  void add(int quantity) =>
      pallets.add((serial: ++_lastSerial, quantity: quantity));

  List<SessionTableRow> get rows => pallets.isEmpty
      ? const []
      : [
          SessionTableRow(
            productTypeId: _productId,
            productTypeName: _composite,
            completedPalletCount: pallets.length,
            completedPackageCount: pallets.fold(0, (s, p) => s + p.quantity),
            loosePackageCount: 0,
          ),
        ];

  BootstrapLineState line() => _lineState(rows);

  SessionProductionDetail detail() => SessionProductionDetail(
    lineId: _lineId,
    authorizationId: 900,
    groups: pallets.isEmpty
        ? const []
        : [
            SessionProductTypeGroup(
              productTypeId: _productId,
              productTypeName: _composite,
              productTypePrefix: '004',
              completedPalletCount: pallets.length,
              pallets: [
                for (final p in pallets.reversed)
                  SessionPalletDetail(
                    palletId: p.serial,
                    scannedValue: '004${p.serial.toString().padLeft(9, '0')}',
                    serialNumber: p.serial.toString().padLeft(9, '0'),
                    quantity: p.quantity,
                    sourceType: 'PRODUCTION_LINE',
                    createdAt: DateTime.utc(2026, 9, 16, 8),
                    createdAtDisplay: '2026-09-16',
                  ),
              ],
            ),
          ],
  );
}

BootstrapLineState _lineState(List<SessionTableRow> rows) => BootstrapLineState(
  lineId: _lineId,
  lineNumber: 1,
  lineName: 'خط أ',
  lineDisplayName: 'خط أ',
  isAuthorized: true,
  authorizedOperator: const Operator(id: 1, name: 'Operator 1'),
  lineUiMode: 'AUTHORIZED',
  currentPlanItemId: 912,
  currentPlanItemProductTypeId: _productId,
  currentPlanItemProductName: _composite,
  sessionTable: rows,
);

class _Harness {
  final FakePalletizingRepository repo = FakePalletizingRepository();
  late final PalletizingProvider provider = PalletizingProvider(
    repo,
    FakeAuthStorage(),
    FakeNotifications(),
  );
  final _Backend backend;

  _Harness(List<int> quantities) : backend = _Backend(quantities) {
    repo.bootstrapFn = () =>
        BootstrapResponse(productTypes: [_yellow], lines: [backend.line()]);
    repo.lineStateFn = (_) => backend.line();
    repo.sessionDetailFn = (_) async => backend.detail();
  }

  SessionTableRow? get summary {
    final rows = provider.getSessionTable(_lineId);
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> sse(String reason, {String id = 'e'}) =>
      provider.refreshFromSseEvents([
        PalletizingAppSseEvent(
          eventId: id,
          reason: reason,
          palletizingLineId: _lineId,
        ),
      ]);
}

PalletCreateResponse _created(int serial, int quantity) => PalletCreateResponse(
  palletId: serial,
  scannedValue: '004${serial.toString().padLeft(9, '0')}',
  operator: const Operator(id: 1, name: 'Operator 1'),
  productType: _yellow,
  productionLine: const ProductionLine(
    id: _lineId,
    name: 'خط أ',
    code: 'L1',
    lineNumber: 1,
  ),
  quantity: quantity,
  currentDestination: 'PRODUCTION',
  createdAt: DateTime.utc(2026, 9, 16, 9),
  createdAtDisplay: '2026-09-16',
);

void main() {
  group('Shift summary follows every pallet mutation', () {
    test('create pallet → summary shows the new backend totals', () async {
      final h = _Harness([12, 12, 12, 12, 12]);
      await h.provider.loadBootstrap();
      expect(h.summary!.completedPalletCount, 5);

      h.repo.createSuccessFn = (call) {
        h.backend.add(call.quantity);
        return _created(h.backend.pallets.last.serial, call.quantity);
      };
      await h.provider.createPallet(
        lineId: _lineId,
        productTypeId: _productId,
        quantity: 12,
        expectedPlanItemId: 912,
      );

      expect(h.summary!.completedPalletCount, 6);
      expect(h.summary!.completedPackageCount, 72);
    });

    test('quantity edited elsewhere → packages update from a targeted '
        '/state read', () async {
      final h = _Harness([12, 12, 12, 12, 12]);
      await h.provider.loadBootstrap();
      final bootstraps = h.repo.bootstrapCalls;

      h.backend.pallets[2] = (serial: h.backend.pallets[2].serial, quantity: 9);
      await h.sse('PALLET_QUANTITY_UPDATED');

      expect(h.summary!.completedPalletCount, 5);
      expect(h.summary!.completedPackageCount, 57);
      expect(h.repo.bootstrapCalls, bootstraps);
    });

    test(
      'operator-app void (PALLET_VOIDED) → pallet count drops at once',
      () async {
        final h = _Harness([12, 12, 12, 12, 12]);
        await h.provider.loadBootstrap();

        h.backend.pallets.removeLast();
        await h.sse('PALLET_VOIDED');

        expect(h.summary!.completedPalletCount, 4);
        expect(h.summary!.completedPackageCount, 48);
      },
    );

    test('admin cancellation (LINE_STATE_CHANGED) → bootstrap shows the lower '
        'count', () async {
      final h = _Harness([12, 12, 12, 12, 12]);
      await h.provider.loadBootstrap();

      h.backend.pallets.removeAt(0);
      await h.sse('LINE_STATE_CHANGED');

      expect(h.summary!.completedPalletCount, 4);
      expect(h.repo.bootstrapCalls, 2);
    });

    test('cancelling the last pallet of a product removes its row', () async {
      final h = _Harness([12]);
      await h.provider.loadBootstrap();

      h.backend.pallets.clear();
      await h.sse('PALLET_VOIDED');

      expect(h.provider.getSessionTable(_lineId), isEmpty);
    });

    test(
      'a rejected create leaves the summary at the backend values',
      () async {
        final h = _Harness([12, 12, 12, 12, 12]);
        await h.provider.loadBootstrap();
        final revision = h.provider.sessionDataRevision(_lineId);

        h.repo.createPalletError = ApiException(
          code: 'LINE_BLOCKED',
          message: 'blocked',
          statusCode: 409,
        );
        await expectLater(
          h.provider.createPallet(
            lineId: _lineId,
            productTypeId: _productId,
            quantity: 12,
            expectedPlanItemId: 912,
          ),
          throwsA(isA<ApiException>()),
        );

        expect(h.summary!.completedPalletCount, 5);
        expect(h.summary!.completedPackageCount, 60);
        expect(h.provider.sessionDataRevision(_lineId), revision);
      },
    );

    test('a failed refresh keeps the last backend values', () async {
      final h = _Harness([12, 12, 12]);
      await h.provider.loadBootstrap();

      h.repo.lineStateFn = (_) =>
          throw ApiException(code: 'NETWORK_ERROR', message: 'offline');
      await h.sse('PALLET_VOIDED');

      expect(h.summary!.completedPalletCount, 3);
    });
  });

  group('Out-of-order responses never roll the summary back', () {
    test('a bootstrap sent before a cancellation cannot overwrite the /state '
        'read its SSE frame triggered', () async {
      final h = _Harness([12, 12, 12, 12, 12]);
      await h.provider.loadBootstrap();

      // A safety-tick bootstrap leaves with the pre-cancel state...
      final slowBootstrap = Completer<BootstrapResponse>();
      final staleSnapshot = BootstrapResponse(
        productTypes: [_yellow],
        lines: [h.backend.line()],
      );
      h.repo.bootstrapAsyncFn = () => slowBootstrap.future;
      final tick = h.provider.refreshBootstrap();

      // ...the cancellation commits and its frame is handled first...
      h.backend.pallets.removeLast();
      await h.sse('PALLET_VOIDED');
      expect(h.summary!.completedPalletCount, 4);

      // ...and the old bootstrap lands last.
      slowBootstrap.complete(staleSnapshot);
      await tick;

      expect(h.summary!.completedPalletCount, 4);
    });

    test('rapid mutations: /state responses landing in reverse order keep the '
        'newest totals', () async {
      final h = _Harness([12, 12, 12, 12, 12]);
      await h.provider.loadBootstrap();

      final pending = <Completer<BootstrapLineState>>[];
      h.repo.lineStateAsyncFn = (_) {
        final c = Completer<BootstrapLineState>();
        pending.add(c);
        return c.future;
      };

      final snapshots = <BootstrapLineState>[];
      final refreshes = <Future<void>>[];
      for (var i = 0; i < 3; i++) {
        h.backend.pallets.removeLast();
        snapshots.add(h.backend.line()); // 4, 3, 2 pallets
        refreshes.add(h.sse('PALLET_VOIDED', id: 'v$i'));
      }

      pending[2].complete(snapshots[2]);
      pending[0].complete(snapshots[0]);
      pending[1].complete(snapshots[1]);
      await Future.wait(refreshes);

      expect(h.summary!.completedPalletCount, 2);
    });

    test('an older response still applies when the newer read fails', () async {
      final h = _Harness([12, 12, 12]);
      await h.provider.loadBootstrap();

      final older = Completer<BootstrapLineState>();
      final newer = Completer<BootstrapLineState>();
      final handout = [older, newer];
      h.repo.lineStateAsyncFn = (_) => handout.removeAt(0).future;

      h.backend.pallets.removeLast();
      final a = h.sse('PALLET_VOIDED', id: 'a');
      final b = h.sse('PALLET_VOIDED', id: 'b');

      newer.completeError(ApiException(code: 'TIMEOUT', message: 'slow'));
      older.complete(h.backend.line());
      await Future.wait([a, b]);

      expect(h.summary!.completedPalletCount, 2);
    });
  });

  group('sessionDataRevision', () {
    test('moves only when the summary rows change', () async {
      final h = _Harness([12, 12]);
      await h.provider.loadBootstrap();
      final start = h.provider.sessionDataRevision(_lineId);

      await h.sse('PALLET_CREATED', id: 'same');
      expect(h.provider.sessionDataRevision(_lineId), start);

      h.backend.add(12);
      await h.sse('PALLET_CREATED', id: 'more');
      expect(h.provider.sessionDataRevision(_lineId), start + 1);
    });
  });

  group('SessionPalletDetail pallet number', () {
    test('uses the full scannedValue, prefix included', () {
      final pallet = SessionPalletDetailModel.fromJson(const {
        'palletId': 51,
        'scannedValue': '004000000051',
        'serialNumber': '000000051',
        'quantity': 12,
        'sourceType': 'PRODUCTION_LINE',
        'createdAt': '2026-09-16T08:00:00Z',
        'createdAtDisplay': '2026-09-16',
      });
      expect(pallet.palletNumber, '004000000051');
    });

    test('a response without scannedValue does not crash', () {
      final noFull = SessionPalletDetailModel.fromJson(const {
        'palletId': 51,
        'serialNumber': '000000051',
        'quantity': 12,
        'createdAt': '2026-09-16T08:00:00Z',
      });
      expect(noFull.palletNumber, '000000051');

      final neither = SessionPalletDetailModel.fromJson(const {
        'palletId': 52,
        'scannedValue': null,
        'serialNumber': null,
        'quantity': 12,
        'createdAt': '2026-09-16T08:00:00Z',
      });
      expect(neither.palletNumber, '');
    });
  });

  group('Production detail dialog', () {
    const line = PalletizingLine(lineId: _lineId, lineNumber: 1);

    Future<_Harness> openDialog(WidgetTester tester, _Harness h) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await h.provider.loadBootstrap();
      await tester.pumpWidget(
        ChangeNotifierProvider<PalletizingProvider>.value(
          value: h.provider,
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
      // Fixed pumps: a held first read shows an endless spinner, which
      // pumpAndSettle would wait on forever.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return h;
    }

    testWidgets('shows full pallet numbers and the product name only', (
      tester,
    ) async {
      await openDialog(tester, _Harness([12, 12]));

      expect(find.text('004000000051'), findsOneWidget);
      expect(find.text('004000000052'), findsOneWidget);
      expect(find.text('000000051'), findsNothing);
      expect(find.text('TT-4 B600 Yellow'), findsOneWidget);
      expect(find.textContaining('/ Yellow /'), findsNothing);
    });

    testWidgets('re-reads in place when the summary changes while open', (
      tester,
    ) async {
      final h = await openDialog(tester, _Harness([12, 12, 12, 12, 12]));
      expect(find.text('5 طبلية'), findsOneWidget);

      final cancelled = h.backend.pallets.removeLast();
      await h.sse('PALLET_VOIDED');
      await tester.pumpAndSettle();

      expect(h.summary!.completedPalletCount, 4);
      expect(find.text('4 طبلية'), findsOneWidget);
      expect(
        find.text('004${cancelled.serial.toString().padLeft(9, '0')}'),
        findsNothing,
      );
      expect(h.repo.sessionDetailLineIds, [_lineId, _lineId]);
    });

    testWidgets('a slow detail read cannot overwrite a newer one', (
      tester,
    ) async {
      final h = _Harness([12, 12, 12]);
      final reads = <Completer<SessionProductionDetail>>[];
      h.repo.sessionDetailFn = (_) {
        final c = Completer<SessionProductionDetail>();
        reads.add(c);
        return c.future;
      };
      await openDialog(tester, h);
      reads[0].complete(h.backend.detail());
      await tester.pumpAndSettle();
      expect(find.text('3 طبلية'), findsOneWidget);

      // Two changes in a row start two re-reads...
      h.backend.pallets.removeLast();
      final afterFirst = h.backend.detail();
      await h.sse('PALLET_VOIDED', id: 'one');
      h.backend.pallets.removeLast();
      final afterSecond = h.backend.detail();
      await h.sse('PALLET_VOIDED', id: 'two');
      expect(reads, hasLength(3));

      // ...and the older one answers last.
      reads[2].complete(afterSecond);
      await tester.pumpAndSettle();
      reads[1].complete(afterFirst);
      await tester.pumpAndSettle();

      expect(find.text('1 طبلية'), findsOneWidget);
    });
  });
}
