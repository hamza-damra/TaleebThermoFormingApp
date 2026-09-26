// PRODUCTION → TRANSIT («الرصيف») move (V210) — widget tests.
//
// docs/FRONTEND_HANDOFF_PALLETIZING_APP_PRODUCTION_TO_TRANSIT_MOVE.md §4, as
// corrected for the Palletizing App:
//   1. one full-width «نقل إلى الرصيف» action opening the scanner — no
//      pending-pallets counter and no pending-pallets dialog;
//   2. the create-blocked / logout-blocked dialog lists the blockers; a
//      card's «نقل إلى الرصيف» opens the scanner for THAT pallet and moves
//      only after a matching fresh scan / typed number;
//   3. row states and the registration action follow the backend's pending
//      list, never local flags;
//   4. the shift production detail shows «تم النقل إلى الرصيف» for TRANSIT.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/core/constants/production_transit_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/theme.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/first_pallet_context.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizing_line.dart';
import 'package:taleeb_thermoforming/domain/entities/printer_config.dart';
import 'package:taleeb_thermoforming/domain/entities/production_transit.dart';
import 'package:taleeb_thermoforming/domain/entities/session_production_detail.dart';
import 'package:taleeb_thermoforming/domain/repositories/preset_repository.dart';
import 'package:taleeb_thermoforming/domain/repositories/printer_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/manager_announcement_notifier.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/providers/printing_provider.dart';
import 'package:taleeb_thermoforming/presentation/screens/palletizing_screen.dart';
import 'package:taleeb_thermoforming/presentation/screens/transit_scan_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/palletizer_pin_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/session_drilldown_dialog.dart';
import 'package:taleeb_thermoforming/presentation/widgets/transit/production_blockers_dialog.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

const _line = 11; // خط أ
const _product = 31; // line 11's plan product
const _shiftLine = 3120;
const _pallet = '101000000123';
const _otherPallet = '101000000124';
const _thirdPallet = '101000000125';

class _Screen {
  _Screen(this.repo, this.auth, this.provider);

  final FakePalletizingRepository repo;
  final FakeAuthStorage auth;
  final PalletizingProvider provider;
}

List<BootstrapLineState> _lines() => [
  skewedLine(1, planItemId: 912, planProductId: 31, packagesPerPallet: 120),
  skewedLine(2, planItemId: 922, planProductId: 32, packagesPerPallet: 120),
];

/// A pallet of line 11's plan product on its current shift-line.
ProductionPendingPallet _pending(String scannedValue, {int palletId = 1}) =>
    ProductionPendingPallet(
      palletId: palletId,
      scannedValue: scannedValue,
      productTypeId: _product,
      productTypeName: 'علبة 500 مل شفاف للاستخدام اليومي',
      thermoformingShiftLineId: _shiftLine,
      currentLocation: 'PRODUCTION',
      producedAt: DateTime.utc(2026, 9, 24, 11, 40),
      producedAtDisplay: '2026-09-24، 02:40 مساءً',
      palletizerName: 'محمد',
    );

Map<String, dynamic> _palletJson(String scannedValue, {int palletId = 1}) => {
  'palletId': palletId,
  'scannedValue': scannedValue,
  'productTypeId': _product,
  'productTypeName': 'علبة 500 مل شفاف للاستخدام اليومي',
  'thermoformingShiftLineId': _shiftLine,
  'currentLocation': 'PRODUCTION',
  'producedAt': '2026-09-24T11:40:00Z',
  'palletizerName': 'محمد',
  'inherited': false,
};

ApiException _createBlocked(List<String> pallets) => ApiException(
  code: 'PREVIOUS_PALLET_STILL_AT_PRODUCTION',
  message: 'x',
  statusCode: 409,
  details: {
    'thermoformingShiftLineId': _shiftLine,
    'productTypeId': _product,
    'blockingPalletCount': pallets.length,
    'blockingPallets': [
      for (var i = 0; i < pallets.length; i++)
        _palletJson(pallets[i], palletId: i + 1),
    ],
  },
);

ProductionPalletBlockers _blockers(List<String> pallets) =>
    ProductionPalletBlockers(
      totalCount: pallets.length,
      productTypeId: _product,
      lines: [
        ProductionPendingLine(
          palletizingLineId: _line,
          thermoformingShiftLineId: _shiftLine,
          pendingCount: pallets.length,
          pallets: [
            for (var i = 0; i < pallets.length; i++)
              _pending(pallets[i], palletId: i + 1),
          ],
        ),
      ],
    );

/// The backend's pending list for line 11 — what it serves right now.
void _serveOnLine(FakePalletizingRepository repo, List<String> pallets) {
  repo.pendingFn = (_) => pendingList({
    _line: [
      for (var i = 0; i < pallets.length; i++)
        _pending(pallets[i], palletId: i + 1),
    ],
  });
}

Future<_Screen> _pump(
  WidgetTester tester, {
  Set<int> sessionLines = const {_line},
  Widget? home,
  FakePalletizingRepository? repo,
  Size size = const Size(800, 1280),
}) async {
  installGoogleFontsTestHarness();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  repo ??= FakePalletizingRepository();
  final auth = FakeAuthStorage();
  for (final id in sessionLines) {
    auth.tokens[id] = 'token-$id';
  }
  repo.sessionFn = (id) =>
      auth.tokens.containsKey(id) ? activeSession(id) : null;
  final byId = {for (final l in _lines()) l.lineId: l};
  repo.bootstrapFn = () => skewedBootstrap(_lines());
  repo.lineStateFn = (id) => byId[id]!;
  var ids = 0;
  final provider = PalletizingProvider(
    repo,
    auth,
    FakeNotifications(),
    transitRetryDelay: Duration.zero,
    clientRequestIdFactory: () => 'req-${++ids}',
  );
  final notifier = ManagerAnnouncementNotifier(
    repo,
    lineIdsSupplier: () => provider.knownOperatingLineIds,
  );
  addTearDown(notifier.dispose);

  if (home != null) await provider.loadBootstrap();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PalletizingProvider>.value(value: provider),
        ChangeNotifierProvider<ManagerAnnouncementNotifier>.value(
          value: notifier,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home ?? const PalletizingScreen(),
      ),
    ),
  );
  await _settle(tester);
  return _Screen(repo, auth, provider);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Finder get _scanButton => find.byKey(const Key('transitScanButton'));
Finder get _retryButton =>
    find.byKey(const Key('productionBlockersRetryButton'));
Finder get _numberField => find.byKey(const Key('transitNumberField'));
Finder _moveButton(String pallet) =>
    find.byKey(ValueKey('blocker-move-$pallet'));
Finder _movedPill(String pallet) =>
    find.byKey(ValueKey('blocker-moved-$pallet'));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

/// Registers a pallet on line 11 and lets the backend refuse it with
/// [blocking]; ends with the blocking dialog on screen.
Future<void> _openCreateBlocked(
  WidgetTester tester,
  _Screen s,
  List<String> blocking,
) async {
  s.repo.firstPalletContextFn = (lineId) => FirstPalletContext(
    lineId: lineId,
    currentPlanItemId: 912,
    currentPlanItemProductTypeId: _product,
  );
  s.repo.createPalletError = _createBlocked(blocking);
  _serveOnLine(s.repo, blocking);
  await tester.tap(find.text('إنشاء طبلية جديدة').first);
  await _settle(tester);
  await tester.tap(find.text('تأكيد'));
  await _settle(tester);
}

/// In the scanner opened from a card: types [number] and submits it.
Future<void> _typeAndSubmit(WidgetTester tester, String number) async {
  await tester.enterText(_numberField, number);
  await tester.tap(find.byKey(const Key('transitSubmitButton')));
  await _settle(tester);
}

void main() {
  setUp(() => TransitScanScreen.debugCameraEnabledOverride = false);
  tearDown(() => TransitScanScreen.debugCameraEnabledOverride = null);

  group('top bar', () {
    testWidgets('hidden until a palletizer is logged in', (tester) async {
      await _pump(tester, sessionLines: const {});

      expect(_scanButton, findsNothing);

      await _unmount(tester);
    });

    testWidgets('no pending counter and no pending-pallets dialog', (
      tester,
    ) async {
      final s = await _pump(tester);
      _serveOnLine(s.repo, [_pallet, _otherPallet]);
      await s.provider.refreshProductionPending();
      await _settle(tester);

      expect(find.byKey(const Key('productionPendingButton')), findsNothing);
      expect(find.byKey(const Key('productionPendingCount')), findsNothing);
      expect(find.text('طبليات في خط الإنتاج'), findsNothing);
      // The underlying pending state is still maintained for the guards.
      expect(s.provider.productionPendingCount, 2);

      await _unmount(tester);
    });

    testWidgets('the one action is full width and opens the scanner', (
      tester,
    ) async {
      final s = await _pump(tester);

      expect(
        find.descendant(of: _scanButton, matching: find.text('نقل إلى الرصيف')),
        findsOneWidget,
      );
      // Full width of the 800 px screen minus the 12 px side padding.
      expect(tester.getSize(_scanButton).width, 800 - 24);

      await tester.tap(_scanButton);
      await _settle(tester);

      expect(find.byType(TransitScanScreen), findsOneWidget);
      expect(_numberField, findsOneWidget);
      expect(s.repo.moveCalls, isEmpty);

      await _unmount(tester);
    });
  });

  group('scanner, manual entry', () {
    testWidgets('Arabic digits are accepted and moved as NUMBER', (
      tester,
    ) async {
      final s = await _pump(tester, home: TransitScanScreen());

      await _typeAndSubmit(tester, '١٠١٠٠٠٠٠٠١٢٣');

      final call = s.repo.moveCalls.single;
      expect(call.identifier, '١٠١٠٠٠٠٠٠١٢٣');
      expect(call.scanType, PalletTransitScanType.number);
      expect(find.text(ProductionTransitStrings.success), findsOneWidget);

      // Next pallet: back to the entry field.
      await tester.tap(find.byKey(const Key('transitScanNextButton')));
      await _settle(tester);
      expect(_numberField, findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('the field takes at most 12 digits', (tester) async {
      final s = await _pump(tester, home: TransitScanScreen());
      String text() => tester.widget<TextField>(_numberField).controller!.text;

      await tester.enterText(_numberField, _pallet);
      expect(text(), _pallet);

      // A 13th digit (ASCII or Arabic-Indic) is refused.
      await tester.enterText(_numberField, '${_pallet}4');
      expect(text(), _pallet);
      await tester.enterText(_numberField, '١٠١٠٠٠٠٠٠١٢٣٤');
      expect(text(), _pallet);

      // A shorter entry is still accepted.
      await tester.enterText(_numberField, '١٠١٠٠٠٠٠٠١٢٣');
      expect(text(), '١٠١٠٠٠٠٠٠١٢٣');
      expect(s.repo.moveCalls, isEmpty);

      await _unmount(tester);
    });

    testWidgets('fewer than 12 digits is rejected locally', (tester) async {
      final s = await _pump(tester, home: TransitScanScreen());

      await _typeAndSubmit(tester, '10100000012');

      expect(
        find.text(ProductionTransitStrings.palletNumberLength),
        findsOneWidget,
      );
      expect(s.repo.moveCalls, isEmpty);

      await _unmount(tester);
    });

    testWidgets('a timeout offers a retry that reuses the request id', (
      tester,
    ) async {
      final s = await _pump(tester, home: TransitScanScreen());
      s.repo.moveResults.addAll([
        ApiException.timeout(),
        ApiException.timeout(),
      ]);

      await _typeAndSubmit(tester, _pallet);
      expect(
        find.text(ProductionTransitStrings.connectionFailed),
        findsOneWidget,
      );

      s.repo.moveResults.add(transitMoveResult(_pallet, replayed: true));
      await tester.tap(find.byKey(const Key('transitRetryButton')));
      await _settle(tester);

      expect(find.text(ProductionTransitStrings.success), findsOneWidget);
      expect(s.repo.moveCalls.map((c) => c.clientRequestId).toSet(), {'req-1'});

      await _unmount(tester);
    });

    testWidgets('an undone replay is never shown as a success', (tester) async {
      final s = await _pump(tester, home: TransitScanScreen());
      s.repo.moveResults.add(
        transitMoveResult(_pallet, replayed: true, movementUndone: true),
      );

      await _typeAndSubmit(tester, _pallet);

      expect(find.text(ProductionTransitStrings.replayUndone), findsOneWidget);
      expect(find.text(ProductionTransitStrings.success), findsNothing);

      await _unmount(tester);
    });

    testWidgets('not at production shows the current location', (tester) async {
      final s = await _pump(tester, home: TransitScanScreen());
      s.repo.moveResults.add(
        ApiException(
          code: 'PALLET_NOT_AT_PRODUCTION',
          message: 'x',
          statusCode: 409,
          details: const {
            'palletId': 55012,
            'scannedValue': _pallet,
            'currentLocation': 'TRANSIT',
          },
        ),
      );

      await _typeAndSubmit(tester, _pallet);

      expect(
        find.text(ProductionTransitStrings.notAtProduction),
        findsOneWidget,
      );
      expect(find.text('الرصيف'), findsOneWidget);

      await _unmount(tester);
    });
  });

  group('create blocked dialog', () {
    testWidgets('still appears and lists the blocking pallets', (tester) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet, _otherPallet]);

      expect(find.byType(ProductionBlockersDialog), findsOneWidget);
      expect(find.text(ProductionTransitStrings.createBlocked), findsOneWidget);
      expect(find.text(_pallet), findsOneWidget);
      expect(find.text(_otherPallet), findsOneWidget);
      expect(
        find.text('${ProductionTransitStrings.remainingLabel}: 2'),
        findsOneWidget,
      );
      expect(_enabled(tester, _retryButton), isFalse);

      await _unmount(tester);
    });

    testWidgets('the card action opens the scanner and sends nothing', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);

      expect(find.byType(TransitScanScreen), findsOneWidget);
      expect(
        find.byKey(const Key('transitSelectedPalletBanner')),
        findsOneWidget,
      );
      // The card's number is never prefilled.
      expect(tester.widget<TextField>(_numberField).controller!.text, isEmpty);
      expect(s.repo.moveCalls, isEmpty);

      await _unmount(tester);
    });

    testWidgets('closing the scanner sends nothing', (tester) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('transitScanCloseButton')));
      await _settle(tester);

      expect(find.byType(TransitScanScreen), findsNothing);
      expect(find.byType(ProductionBlockersDialog), findsOneWidget);
      expect(s.repo.moveCalls, isEmpty);
      expect(_moveButton(_pallet), findsOneWidget);
      expect(_enabled(tester, _retryButton), isFalse);

      await _unmount(tester);
    });

    testWidgets('another pallet\'s number is refused without a request', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);
      await _typeAndSubmit(tester, _otherPallet);

      expect(
        find.text(ProductionTransitStrings.identifierMismatch),
        findsOneWidget,
      );
      expect(s.repo.moveCalls, isEmpty);
      expect(find.byType(TransitScanScreen), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets(
      'a matching number moves; «تم النقل» after the backend confirms; '
      'the same create is re-sent',
      (tester) async {
        final s = await _pump(tester);
        await _openCreateBlocked(tester, s, [_pallet, _otherPallet]);
        s.repo.moveFn = (call) {
          // The backend moved it — its pending list no longer has it.
          _serveOnLine(s.repo, [_otherPallet]);
          return transitMoveResult(
            PalletIdentifier.canonicalize(call.identifier),
          );
        };

        await tester.tap(_moveButton(_pallet));
        await _settle(tester);
        await _typeAndSubmit(tester, _pallet);

        // The typed number is sent — not the card's value on its own.
        final call = s.repo.moveCalls.single;
        expect(call.identifier, _pallet);
        expect(call.scanType, PalletTransitScanType.number);
        expect(find.byType(TransitScanScreen), findsNothing);
        expect(_movedPill(_pallet), findsOneWidget);
        expect(find.text(ProductionTransitStrings.moved), findsOneWidget);
        // The dialog stays open for the remaining pallet.
        expect(
          find.text('${ProductionTransitStrings.remainingLabel}: 1'),
          findsOneWidget,
        );
        expect(_enabled(tester, _retryButton), isFalse);

        // Scan the next blocking pallet.
        s.repo.moveFn = (call) {
          _serveOnLine(s.repo, []);
          return transitMoveResult(
            PalletIdentifier.canonicalize(call.identifier),
          );
        };
        await tester.tap(_moveButton(_otherPallet));
        await _settle(tester);
        await _typeAndSubmit(tester, _otherPallet);

        expect(_movedPill(_otherPallet), findsOneWidget);
        expect(
          find.byKey(const Key('productionBlockersAllResolved')),
          findsOneWidget,
        );
        expect(_enabled(tester, _retryButton), isTrue);

        // The re-sent create ends in an unrelated refusal so the test stops
        // before the success / print dialog.
        s.repo.createPalletError = ApiException(
          code: 'PRODUCTION_PLAN_CURRENT_ITEM_CHANGED',
          message: 'x',
          statusCode: 409,
        );
        await tester.tap(_retryButton);
        await _settle(tester);

        expect(s.repo.createCalls, hasLength(2));
        final first = s.repo.createCalls.first;
        final second = s.repo.createCalls.last;
        expect(second.productTypeId, first.productTypeId);
        expect(second.expectedPlanItemId, first.expectedPlanItemId);
        expect(second.quantity, first.quantity);

        await _unmount(tester);
      },
    );

    testWidgets('registration stays blocked until the backend confirms', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);
      // The move succeeds, but the backend's pending list still has it.
      s.repo.moveFn = (call) => transitMoveResult(_pallet);

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);
      await _typeAndSubmit(tester, _pallet);

      expect(s.repo.moveCalls, hasLength(1));
      expect(_movedPill(_pallet), findsNothing);
      expect(_enabled(tester, _retryButton), isFalse);

      // The next read (e.g. after the SSE frame) confirms it left.
      _serveOnLine(s.repo, []);
      await s.provider.refreshProductionPending();
      await _settle(tester);

      expect(_movedPill(_pallet), findsOneWidget);
      expect(_enabled(tester, _retryButton), isTrue);

      await _unmount(tester);
    });

    testWidgets('a new same-product pallet at PRODUCTION keeps it blocked', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);
      s.repo.moveFn = (call) {
        _serveOnLine(s.repo, [_thirdPallet]);
        return transitMoveResult(_pallet);
      };

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);
      await _typeAndSubmit(tester, _pallet);

      expect(_movedPill(_pallet), findsOneWidget);
      // The backend reports another blocker — listed, and still blocking.
      expect(_moveButton(_thirdPallet), findsOneWidget);
      expect(_enabled(tester, _retryButton), isFalse);

      await _unmount(tester);
    });

    testWidgets('a pallet moved by a driver is reflected after a refresh', (
      tester,
    ) async {
      final s = await _pump(tester);
      await _openCreateBlocked(tester, s, [_pallet]);

      _serveOnLine(s.repo, []);
      await s.provider.refreshProductionPending();
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('blocker-left-$_pallet')),
        findsOneWidget,
      );
      expect(s.repo.moveCalls, isEmpty);
      expect(_enabled(tester, _retryButton), isTrue);

      await _unmount(tester);
    });

    testWidgets('a failed status read keeps registration blocked', (
      tester,
    ) async {
      final s = await _pump(tester);
      s.repo.firstPalletContextFn = (lineId) => FirstPalletContext(
        lineId: lineId,
        currentPlanItemId: 912,
        currentPlanItemProductTypeId: _product,
      );
      s.repo.createPalletError = _createBlocked([_pallet]);
      s.repo.pendingFn = (_) => throw ApiException.network();
      await tester.tap(find.text('إنشاء طبلية جديدة').first);
      await _settle(tester);
      await tester.tap(find.text('تأكيد'));
      await _settle(tester);

      expect(
        find.byKey(const Key('productionBlockersCheckFailed')),
        findsOneWidget,
      );
      expect(_enabled(tester, _retryButton), isFalse);

      await _unmount(tester);
    });
  });

  group('blocking dialog layout', () {
    Future<_Screen> host(
      WidgetTester tester,
      Size size,
      List<String> pallets,
    ) async {
      late _Screen s;
      final repo = FakePalletizingRepository();
      _serveOnLine(repo, pallets);
      s = await _pump(
        tester,
        repo: repo,
        size: size,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ProductionBlockersDialog.show(
                context,
                lineId: _line,
                kind: ProductionBlockerKind.create,
                blockers: _blockers(pallets),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      return s;
    }

    testWidgets('fits a small Android screen: scrolls, footer reachable', (
      tester,
    ) async {
      final pallets = [for (var i = 0; i < 8; i++) '10100000012$i'];
      await host(tester, const Size(360, 640), pallets);

      expect(tester.takeException(), isNull);
      // The footer stays on screen while the list scrolls.
      final footer = tester.getRect(_retryButton);
      expect(footer.bottom, lessThanOrEqualTo(640));
      expect(footer.top, greaterThan(0));
      await tester.drag(
        find.byKey(const Key('productionBlockersList')),
        const Offset(0, -600),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(pallets.last), findsOneWidget);
      expect(tester.getRect(_retryButton), footer);

      await _unmount(tester);
    });

    testWidgets('pallet numbers stay on one line in a narrow card', (
      tester,
    ) async {
      await host(tester, const Size(320, 640), [_pallet]);

      final number = tester.renderObject<RenderBox>(find.text(_pallet));
      final text = tester.widget<Text>(find.text(_pallet));
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      // One line of 16 px monospace text, however narrow the card.
      expect(number.size.height, lessThan(30));
      expect(tester.takeException(), isNull);

      await _unmount(tester);
    });

    testWidgets('uses the app theme colours', (tester) async {
      await host(tester, const Size(800, 1280), [_pallet]);

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, AppTheme.backgroundColor);
      final move = tester.widget<ElevatedButton>(_moveButton(_pallet));
      expect(
        move.style!.backgroundColor!.resolve(const {}),
        AppTheme.primaryColor,
      );

      await _unmount(tester);
    });
  });

  group('logout blocked dialog', () {
    testWidgets('keeps the line logged in, scans, moves, then leaves', (
      tester,
    ) async {
      final s = await _pump(tester);
      _serveOnLine(s.repo, [_pallet]);
      s.repo.logoutErrors[_line] = ApiException(
        code: 'PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS',
        message: 'x',
        statusCode: 409,
        details: {
          'pendingProductionPalletCount': 1,
          'blockedLines': [
            {
              'thermoformingShiftLineId': _shiftLine,
              'palletizingLineId': _line,
              'palletizingLineName': 'خط أ',
              'count': 1,
              'pallets': [_palletJson(_pallet)],
            },
          ],
        },
      );
      s.repo.moveFn = (call) {
        _serveOnLine(s.repo, []);
        return transitMoveResult(_pallet);
      };

      await tester.tap(find.text('مغادرة الآن').first);
      await _settle(tester);
      await tester.tap(find.text('نعم، مغادرة الآن'));
      await _settle(tester);

      expect(find.text(ProductionTransitStrings.logoutBlocked), findsOneWidget);
      expect(s.provider.hasActivePalletizerSession(_line), isTrue);

      await tester.tap(_moveButton(_pallet));
      await _settle(tester);
      expect(s.repo.moveCalls, isEmpty);
      await _typeAndSubmit(tester, _pallet);
      expect(_movedPill(_pallet), findsOneWidget);

      s.repo.logoutErrors.remove(_line);
      await tester.tap(_retryButton);
      await _settle(tester);

      expect(s.repo.logoutLineIds, [_line, _line]);
      expect(s.provider.hasActivePalletizerSession(_line), isFalse);
      expect(find.byType(PalletizerPinScreen), findsWidgets);

      await _unmount(tester);
    });
  });

  group('shift production detail', () {
    Future<void> open(
      WidgetTester tester,
      List<SessionPalletDetail> pallets,
    ) async {
      installGoogleFontsTestHarness();
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = FakePalletizingRepository();
      repo.bootstrapFn = () => skewedBootstrap(_lines());
      repo.lineStateFn = (id) => _lines().firstWhere((l) => l.lineId == id);
      repo.sessionDetailFn = (_) async => SessionProductionDetail(
        lineId: _line,
        authorizationId: 900,
        groups: [
          SessionProductTypeGroup(
            productTypeId: _product,
            productTypeName: 'علبة 500 مل',
            productTypePrefix: '101',
            completedPalletCount: pallets.length,
            pallets: pallets,
          ),
        ],
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
                  onPressed: () => SessionDrilldownDialog.show(
                    context: context,
                    line: const PalletizingLine(lineId: _line, lineNumber: 1),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    SessionPalletDetail pallet(
      int id, {
      String? location,
      String? grindingLabel,
    }) => SessionPalletDetail(
      palletId: id,
      scannedValue: '10100000005$id',
      serialNumber: '00000005$id',
      quantity: 120,
      sourceType: 'FRESH',
      createdAt: DateTime.utc(2026, 9, 24, 8),
      createdAtDisplay: '2026-09-24، 11:00 صباحاً',
      currentLocation: location,
      grindingStatus: grindingLabel == null ? null : 'COMPLETED',
      grindingStatusLabel: grindingLabel,
    );

    testWidgets('«تم النقل إلى الرصيف» only for pallets at TRANSIT', (
      tester,
    ) async {
      await open(tester, [
        pallet(1, location: 'TRANSIT'),
        pallet(2, location: 'PRODUCTION'),
        pallet(3),
        pallet(4, location: 'TRANSIT', grindingLabel: 'تم الجرش'),
      ]);

      expect(find.byKey(const Key('transitLocationChip-1')), findsOneWidget);
      expect(find.byKey(const Key('transitLocationChip-2')), findsNothing);
      expect(find.byKey(const Key('transitLocationChip-3')), findsNothing);
      // Beside the grinding chip, which is unchanged.
      expect(find.byKey(const Key('transitLocationChip-4')), findsOneWidget);
      expect(find.byKey(const Key('grindingStatusChip-4')), findsOneWidget);
      expect(
        find.text(ProductionTransitStrings.movedToTransitBadge),
        findsNWidgets(2),
      );
      // Rows, quantities, times and reprint stay; no move action here.
      expect(find.text('101000000051'), findsOneWidget);
      expect(find.text('120 عبوة'), findsNWidgets(4));
      expect(find.byKey(const Key('reprintPallet-1')), findsOneWidget);
      expect(find.text(ProductionTransitStrings.action), findsNothing);
    });
  });
}

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
