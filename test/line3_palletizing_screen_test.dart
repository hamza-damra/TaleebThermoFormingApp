// LINE_3 handoff §6.10 — widget tests for the N-line palletizing screen.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/presentation/providers/manager_announcement_notifier.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/screens/palletizing_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/line_scoped_route.dart';
import 'package:taleeb_thermoforming/presentation/widgets/production_line_section.dart';
import 'package:taleeb_thermoforming/presentation/widgets/thermoforming_waiting_card.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

class _Screen {
  final FakePalletizingRepository repo;
  final PalletizingProvider provider;
  _Screen(this.repo, this.provider);

  void serve(List<BootstrapLineState> lines) {
    final byId = {for (final l in lines) l.lineId: l};
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (lineId) => byId[lineId]!;
  }
}

Future<_Screen> _pumpScreen(
  WidgetTester tester,
  List<BootstrapLineState> lines, {
  Size size = const Size(800, 1280),
}) async {
  installGoogleFontsTestHarness();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = FakePalletizingRepository();
  final provider = PalletizingProvider(
    repo,
    FakeAuthStorage(),
    FakeNotifications(),
  );
  final screen = _Screen(repo, provider)..serve(lines);
  final notifier = ManagerAnnouncementNotifier(
    repo,
    lineIdsSupplier: () => provider.knownOperatingLineIds,
  );
  addTearDown(notifier.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PalletizingProvider>.value(value: provider),
        ChangeNotifierProvider<ManagerAnnouncementNotifier>.value(
          value: notifier,
        ),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PalletizingScreen(),
      ),
    ),
  );
  await _settle(tester);
  return screen;
}

/// Lets the post-frame bootstrap, tab animations and snackbars run without
/// pumpAndSettle (the PIN field's cursor blinks forever).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the screen so its clock timer is cancelled.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(TabBar), matching: find.text(label));

int _tabCount(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).tabs.length;

int _selectedTabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  testWidgets('three tabs in server order, right to left, with server labels', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3, waitingForOperator: true),
    ]);

    expect(_tabCount(tester), 3);
    final a = tester.getCenter(_tab('خط أ')).dx;
    final b = tester.getCenter(_tab('خط ب')).dx;
    final c = tester.getCenter(_tab('خط ج')).dx;
    // RTL: the first line sits on the right.
    expect(a, greaterThan(b));
    expect(b, greaterThan(c));
    expect(find.textContaining('ماكنة'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('two tabs when bootstrap has two lines', (tester) async {
    await _pumpScreen(tester, [skewedLine(1), skewedLine(2)]);

    expect(_tabCount(tester), 2);
    expect(_tab('خط ج'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('tab count 2 → 3 → 2 keeps the selected lineId', (tester) async {
    final screen = await _pumpScreen(tester, [skewedLine(1), skewedLine(2)]);

    await tester.tap(_tab('خط ب'));
    await _settle(tester);
    expect(screen.provider.selectedLineId, 12);

    // Admin enables LINE_3.
    screen.serve([skewedLine(1), skewedLine(2), skewedLine(3)]);
    await screen.provider.refreshBootstrap();
    await _settle(tester);

    expect(_tabCount(tester), 3);
    expect(screen.provider.selectedLineId, 12);
    expect(_selectedTabIndex(tester), 1);
    expect(find.text('تمت إضافة خط ج'), findsOneWidget);

    // Admin disables it again while another tab is selected → snackbar only.
    screen.serve([skewedLine(1), skewedLine(2)]);
    await screen.provider.refreshBootstrap();
    await _settle(tester);

    expect(_tabCount(tester), 2);
    expect(screen.provider.selectedLineId, 12);
    expect(_selectedTabIndex(tester), 1);
    expect(find.text('تم إيقاف الخط'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('wide screens use panes only when every pane fits', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3),
    ], size: const Size(1400, 900));

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ProductionLineSection), findsNWidgets(3));

    await _unmount(tester);
  });

  testWidgets('three lines at 1200 dp fall back to tabs', (tester) async {
    await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3),
    ], size: const Size(1200, 900));

    expect(find.byType(TabBar), findsOneWidget);
    expect(_tabCount(tester), 3);

    await _unmount(tester);
  });

  testWidgets('the waiting card on line 3 shows the resolved label', (
    tester,
  ) async {
    final screen = await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3, waitingForOperator: true),
    ]);

    await tester.tap(_tab('خط ج'));
    await _settle(tester);
    expect(screen.provider.selectedLineId, 13);

    final card = find.byType(ThermoformingWaitingCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('خط ج')),
      findsOneWidget,
    );
    expect(find.textContaining('ماكنة'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('switching off the selected line shows the notice and selects '
      'the first line', (tester) async {
    final screen = await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3),
    ]);
    await tester.tap(_tab('خط ج'));
    await _settle(tester);

    screen.serve([skewedLine(1), skewedLine(2)]);
    await screen.provider.refreshBootstrap();
    await _settle(tester);

    expect(find.text('تم إيقاف الخط'), findsOneWidget);
    expect(
      find.text('خط ج غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.'),
      findsOneWidget,
    );

    await tester.tap(find.text('حسناً'));
    await _settle(tester);

    expect(find.text('تم إيقاف الخط'), findsNothing);
    expect(_tabCount(tester), 2);
    expect(screen.provider.selectedLineId, 11);
    expect(_selectedTabIndex(tester), 0);

    await _unmount(tester);
  });

  testWidgets('a dialog that belongs to a switched-off line closes itself', (
    tester,
  ) async {
    final screen = await _pumpScreen(tester, [
      skewedLine(1),
      skewedLine(2),
      skewedLine(3),
    ]);
    await tester.tap(_tab('خط ج'));
    await _settle(tester);

    showDialog<void>(
      context: tester.element(find.byType(ProductionLineSection).first),
      builder: (_) => const LineScopedRoute(
        lineId: 13,
        child: AlertDialog(title: Text('line 13 dialog')),
      ),
    );
    await _settle(tester);
    expect(find.text('line 13 dialog'), findsOneWidget);

    screen.serve([skewedLine(1), skewedLine(2)]);
    await screen.provider.refreshBootstrap();
    await _settle(tester);

    expect(find.text('line 13 dialog'), findsNothing);
    expect(find.text('تم إيقاف الخط'), findsOneWidget);

    await tester.tap(find.text('حسناً'));
    await _settle(tester);
    await _unmount(tester);
  });
}
