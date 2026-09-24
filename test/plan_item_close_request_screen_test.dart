// Plan-item close handshake (V190) — Palletizing screen tests: the blocking
// decision dialog, the completing-pallets banner and the final confirmation,
// driven through the real PalletizingScreen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/core/constants/plan_item_close_request_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/core/services/palletizing_event.dart';
import 'package:taleeb_thermoforming/core/services/sse_client.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/entities/plan_item_close_request.dart';
import 'package:taleeb_thermoforming/presentation/providers/manager_announcement_notifier.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/screens/palletizing_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/palletizer_pin_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/plan_item_close_completing_banner.dart';
import 'package:taleeb_thermoforming/presentation/widgets/plan_item_close_request_dialog.dart';

import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

const _line = 11; // خط أ
const _otherLine = 12; // خط ب
const _requestId = 3021;

/// Controllable stand-in for the device-level SSE client.
class _FakeSseClient implements SseClient {
  final _states = StreamController<SseConnectionState>.broadcast();
  final _events = StreamController<PalletizingAppSseEvent>.broadcast();
  final _announcements =
      StreamController<UrgentManagerAnnouncementEvent>.broadcast();

  @override
  Stream<SseConnectionState> get connectionState => _states.stream;
  @override
  Stream<PalletizingAppSseEvent> get events => _events.stream;
  @override
  Stream<UrgentManagerAnnouncementEvent> get announcements =>
      _announcements.stream;
  @override
  SseConnectionState get currentState => SseConnectionState.connected;
  @override
  String get path => '/palletizing-line/app-events';
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> dispose() async {
    await _states.close();
    await _events.close();
    await _announcements.close();
  }

  void emit(String eventId, int lineId, String reason) => _events.add(
    PalletizingAppSseEvent(
      eventId: eventId,
      type: 'LINE_STATE_CHANGED',
      reason: reason,
      palletizingLineId: lineId,
      thermoformingLineId: 4,
    ),
  );
}

class _Screen {
  _Screen(this.repo, this.auth, this.provider, this.sse);

  final FakePalletizingRepository repo;
  final FakeAuthStorage auth;
  final PalletizingProvider provider;
  final _FakeSseClient? sse;

  final Map<int, BootstrapLineState> served = {};

  void serve(List<BootstrapLineState> lines) {
    served
      ..clear()
      ..addEntries(lines.map((l) => MapEntry(l.lineId, l)));
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (id) => served[id]!;
  }
}

List<BootstrapLineState> _lines() => [
  skewedLine(1, planItemId: 912, planProductId: 31),
  skewedLine(2, planItemId: 922, planProductId: 32),
];

Future<_Screen> _pump(
  WidgetTester tester, {
  Set<int> sessionLines = const {_line},
  PlanItemCloseRequest? request,
  bool withSse = false,
}) async {
  installGoogleFontsTestHarness();
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = FakePalletizingRepository();
  final auth = FakeAuthStorage();
  for (final id in sessionLines) {
    auth.tokens[id] = 'token-$id';
  }
  repo.sessionFn = (id) =>
      auth.tokens.containsKey(id) ? activeSession(id) : null;
  if (request != null) {
    repo.activeCloseRequests[request.palletizingLineId] = request;
  }
  final sse = withSse ? _FakeSseClient() : null;
  final provider = PalletizingProvider(
    repo,
    auth,
    FakeNotifications(),
    sseClient: sse,
    closeDecisionRetryDelay: Duration.zero,
  );
  final screen = _Screen(repo, auth, provider, sse)..serve(_lines());
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

/// Fixed-step pumps — the PIN cursor and progress spinners animate forever,
/// so `pumpAndSettle` would time out. Also lets the 250 ms SSE debounce fire.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the screen (cancels its clock) and stops the provider's timers.
Future<void> _unmount(WidgetTester tester, _Screen screen) async {
  await tester.pumpWidget(const SizedBox.shrink());
  screen.provider.dispose();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

PlanItemCloseRequest _waiting({int lineId = _line, int id = _requestId}) =>
    closeRequest(id: id, lineId: lineId);

PlanItemCloseRequest _completing({int lineId = _line}) => closeRequest(
  lineId: lineId,
  status: PlanItemCloseRequestStatus.palletizerCompletingPallets,
);

final _dialog = find.byType(PlanItemCloseRequestDialog);
final _finalDialog = find.byType(PlanItemCloseFinalConfirmDialog);
final _banner = find.byType(PlanItemCloseCompletingBanner);

Finder _inDialog(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

Finder _bannerText(String text) =>
    find.descendant(of: _banner, matching: find.text(text));

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          )
          .first,
    );

/// A one-shot notice. Two lines are rendered, so the screen names the line.
Finder _notice(String text, {String line = 'خط أ'}) =>
    find.text('$line: $text');

ApiException _api(String code, [int status = 409]) =>
    ApiException(code: code, message: 'English text', statusCode: status);

void main() {
  group('WAITING_FOR_PALLETIZER_DECISION — blocking dialog', () {
    testWidgets('app start with a pending request shows ONE dialog with the '
        'exact copy and the backend context', (tester) async {
      final s = await _pump(tester, request: _waiting());

      expect(_dialog, findsOneWidget);
      expect(
        _inDialog(PlanItemCloseRequestStrings.dialogTitle),
        findsOneWidget,
      );
      expect(_inDialog(PlanItemCloseRequestStrings.dialogBody), findsOneWidget);
      expect(
        _inDialog(PlanItemCloseRequestStrings.confirmAllAction),
        findsOneWidget,
      );
      expect(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
        findsOneWidget,
      );
      expect(_inDialog('خط أ'), findsOneWidget);
      final context = find.descendant(
        of: _dialog,
        matching: find.byType(PlanItemCloseRequestContext),
      );
      expect(
        find.descendant(
          of: context,
          matching: find.textContaining('علبة 500 مل شفاف', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: context,
          matching: find.textContaining('1840 / 2000', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: context,
          matching: find.textContaining('محمد أحمد', findRichText: true),
        ),
        findsOneWidget,
      );

      await _unmount(tester, s);
    });

    testWidgets('an outside tap and the back button cannot dismiss it', (
      tester,
    ) async {
      final s = await _pump(tester, request: _waiting());

      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);
      expect(_dialog, findsOneWidget);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      expect(await navigator.maybePop(), isTrue); // handled by PopScope…
      await _settle(tester);
      expect(_dialog, findsOneWidget); // …and refused.

      expect(s.repo.confirmCalls, isEmpty);
      expect(s.repo.morePalletsCalls, isEmpty);
      await _unmount(tester, s);
    });

    testWidgets('it appears after PIN login when the request already existed', (
      tester,
    ) async {
      final s = await _pump(tester, sessionLines: const {});
      expect(find.byType(PalletizerPinScreen), findsWidgets);
      expect(_dialog, findsNothing);
      expect(s.repo.closeRequestReads, isEmpty, reason: 'nothing before login');

      s.repo.activeCloseRequests[_line] = _waiting();
      s.repo.authFn = (id) => PalletizerAuthResult(
        session: activeSession(id),
        sessionToken: 'fresh-token',
      );
      await s.provider.palletizerAuth(_line, '1234');
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      expect(s.repo.closeRequestReads.last.sessionToken, 'fresh-token');
      await _unmount(tester, s);
    });

    testWidgets('it appears after an SSE frame and the REST read', (
      tester,
    ) async {
      final s = await _pump(tester, withSse: true);
      expect(_dialog, findsNothing);

      s.repo.activeCloseRequests[_line] = _waiting();
      s.sse!.emit('e1', _line, 'PLAN_ITEM_CLOSE_REQUESTED');
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      await _unmount(tester, s);
    });

    testWidgets('it appears after the app returns from the background', (
      tester,
    ) async {
      final s = await _pump(tester, withSse: true);
      expect(_dialog, findsNothing);

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        await _lifecycle(tester, state);
      }
      // The operator requested the close while the tablet was backgrounded;
      // no frame reached this device.
      s.repo.activeCloseRequests[_line] = _waiting();
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        await _lifecycle(tester, state);
      }
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      await _unmount(tester, s);
    });

    testWidgets('repeated reads, SSE bursts and rebuilds never stack a second '
        'dialog', (tester) async {
      final s = await _pump(tester, request: _waiting(), withSse: true);
      expect(_dialog, findsOneWidget);

      for (var i = 0; i < 3; i++) {
        s.sse!.emit('dup-$i', _line, 'PLAN_ITEM_CLOSE_REQUESTED');
      }
      await s.provider.refreshCloseRequest(_line);
      await s.provider.refreshCloseRequest(_line);
      await s.provider.refreshLineState(_line);
      await s.provider.refreshBootstrap();
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _unmount(tester, s);
    });

    testWidgets('a request of another line is never shown', (tester) async {
      final s = await _pump(tester);
      // The read for line 11 answers with a request that belongs to line 12,
      // and line 12 (no session here) has its own request on the backend.
      s.repo.activeCloseRequests[_line] = _waiting(lineId: _otherLine);
      await s.provider.refreshCloseRequest(_line);
      s.repo.activeCloseRequests[_otherLine] = _waiting(lineId: _otherLine);
      await s.provider.refreshCloseRequest(_otherLine);
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(
        s.repo.closeRequestReads.where((c) => c.lineId == _otherLine),
        isEmpty,
      );
      await _unmount(tester, s);
    });
  });

  group('"نعم، تم تسجيل جميع الطبليات"', () {
    testWidgets('calls confirm exactly once, closes the dialog, shows the '
        'confirmed notice and re-reads the line state', (tester) async {
      final s = await _pump(tester, request: _waiting());
      // The backend makes the next item current.
      s.served[_line] = skewedLine(1, planItemId: 913, planProductId: 33);

      await tester.tap(_inDialog(PlanItemCloseRequestStrings.confirmAllAction));
      await _settle(tester);

      expect(s.repo.confirmCalls, hasLength(1));
      expect(s.repo.confirmCalls.single.closeRequestId, _requestId);
      expect(s.repo.morePalletsCalls, isEmpty);
      expect(_dialog, findsNothing);
      expect(_banner, findsOneWidget); // mounted, but renders nothing
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsNothing,
      );
      expect(
        _notice(PlanItemCloseRequestStrings.confirmedNotice),
        findsOneWidget,
      );
      expect(s.provider.getCurrentPlanItemId(_line), 913);
      await _unmount(tester, s);
    });

    testWidgets('shows progress, disables both answers and never '
        'double-submits', (tester) async {
      final s = await _pump(tester, request: _waiting());
      final gate = Completer<void>();
      s.repo.decisionGate = gate;

      await tester.tap(_inDialog(PlanItemCloseRequestStrings.confirmAllAction));
      await tester.pump();

      expect(
        find.descendant(
          of: _dialog,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _dialog,
          matching: find.text(PlanItemCloseRequestStrings.confirmAllAction),
        ),
        findsNothing,
        reason: 'the tapped answer shows the spinner instead of its label',
      );
      expect(
        _button(
          tester,
          PlanItemCloseRequestStrings.morePalletsAction,
        ).onPressed,
        isNull,
      );
      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
        warnIfMissed: false,
      );
      await tester.pump();

      gate.complete();
      await _settle(tester);

      expect(s.repo.confirmCalls, hasLength(1));
      expect(s.repo.morePalletsCalls, isEmpty);
      expect(_dialog, findsNothing);
      await _unmount(tester, s);
    });

    testWidgets('a paused line keeps the dialog open with the reason, and the '
        'answers are usable again', (tester) async {
      final s = await _pump(tester, request: _waiting());
      s.repo.confirmResults.add(_api('THERMOFORMING_LINE_PAUSED'));

      await tester.tap(_inDialog(PlanItemCloseRequestStrings.confirmAllAction));
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      expect(_inDialog(PlanItemCloseRequestStrings.linePaused), findsOneWidget);
      expect(
        _button(tester, PlanItemCloseRequestStrings.confirmAllAction).onPressed,
        isNotNull,
      );
      await _unmount(tester, s);
    });

    testWidgets('an expired session closes the dialog and shows the PIN '
        'screen', (tester) async {
      final s = await _pump(tester, request: _waiting());
      s.repo.confirmResults.add(_api('PALLETIZER_SESSION_REQUIRED', 401));

      await tester.tap(_inDialog(PlanItemCloseRequestStrings.confirmAllAction));
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(find.byType(PalletizerPinScreen), findsWidgets);
      expect(
        _notice(PlanItemCloseRequestStrings.noLongerValidNotice),
        findsNothing,
      );
      await _unmount(tester, s);
    });
  });

  group('"لا، بقيت طبليات للتسجيل"', () {
    testWidgets('calls more-pallets-remain once, closes the blocking dialog, '
        'shows the banner and keeps pallet creation usable', (tester) async {
      final s = await _pump(tester, request: _waiting());

      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
      );
      await _settle(tester);

      expect(s.repo.morePalletsCalls, hasLength(1));
      expect(s.repo.confirmCalls, isEmpty);
      expect(_dialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsOneWidget,
      );
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerBody),
        findsOneWidget,
      );
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerAction),
        findsOneWidget,
      );
      expect(find.byType(PalletizerPinScreen), findsNothing);
      expect(
        _button(tester, 'إنشاء طبلية جديدة').onPressed,
        isNotNull,
        reason: 'the palletizer must be able to register the remaining pallets',
      );
      expect(find.byType(ModalBarrier), findsOneWidget); // only the page's
      await _unmount(tester, s);
    });

    testWidgets('a network failure keeps the dialog with the reason and a '
        'retry succeeds', (tester) async {
      final s = await _pump(tester, request: _waiting());
      s.repo.morePalletsResults.addAll([
        ApiException.network(),
        ApiException.network(),
      ]);

      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
      );
      await _settle(tester);
      expect(_dialog, findsOneWidget);
      expect(_inDialog(ApiException.network().displayMessage), findsOneWidget);

      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
      );
      await _settle(tester);

      expect(s.repo.morePalletsCalls, hasLength(3));
      expect(_dialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('a request on another tab brings that line into view', (
      tester,
    ) async {
      final s = await _pump(
        tester,
        sessionLines: const {_line, _otherLine},
        request: _waiting(lineId: _otherLine),
      );
      expect(s.provider.selectedLineId, _line);
      expect(_inDialog('خط ب'), findsOneWidget);

      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
      );
      await _settle(tester);

      expect(s.repo.morePalletsCalls.single.lineId, _otherLine);
      expect(s.provider.selectedLineId, _otherLine);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });
  });

  group('PALLETIZER_COMPLETING_PALLETS — banner and final confirmation', () {
    testWidgets('restored on start as a banner, never as the blocking dialog', (
      tester,
    ) async {
      final s = await _pump(tester, request: _completing());

      expect(_dialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('the final confirmation shows the exact copy and closes the '
        'item', (tester) async {
      final s = await _pump(tester, request: _completing());

      await tester.tap(_bannerText(PlanItemCloseRequestStrings.bannerAction));
      await _settle(tester);

      expect(_finalDialog, findsOneWidget);
      Finder inFinal(String t) =>
          find.descendant(of: _finalDialog, matching: find.text(t));
      expect(
        inFinal(PlanItemCloseRequestStrings.finalConfirmTitle),
        findsOneWidget,
      );
      expect(
        inFinal(PlanItemCloseRequestStrings.finalConfirmBody),
        findsOneWidget,
      );
      expect(
        inFinal(PlanItemCloseRequestStrings.finalConfirmCancel),
        findsOneWidget,
      );
      expect(
        inFinal(PlanItemCloseRequestStrings.finalConfirmAction),
        findsOneWidget,
      );
      expect(s.repo.confirmCalls, isEmpty, reason: 'nothing before confirm');

      await tester.tap(inFinal(PlanItemCloseRequestStrings.finalConfirmAction));
      await _settle(tester);

      expect(s.repo.confirmCalls, hasLength(1));
      expect(_finalDialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsNothing,
      );
      expect(
        _notice(PlanItemCloseRequestStrings.confirmedNotice),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('"إلغاء" sends nothing and keeps the banner', (tester) async {
      final s = await _pump(tester, request: _completing());

      await tester.tap(_bannerText(PlanItemCloseRequestStrings.bannerAction));
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: _finalDialog,
          matching: find.text(PlanItemCloseRequestStrings.finalConfirmCancel),
        ),
      );
      await _settle(tester);

      expect(_finalDialog, findsNothing);
      expect(s.repo.confirmCalls, isEmpty);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('the full "لا" path: dialog → banner → final confirmation → '
        'item closed', (tester) async {
      final s = await _pump(tester, request: _waiting());

      await tester.tap(
        _inDialog(PlanItemCloseRequestStrings.morePalletsAction),
      );
      await _settle(tester);
      expect(_dialog, findsNothing);

      await tester.tap(_bannerText(PlanItemCloseRequestStrings.bannerAction));
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: _finalDialog,
          matching: find.text(PlanItemCloseRequestStrings.finalConfirmAction),
        ),
      );
      await _settle(tester);

      expect(s.repo.morePalletsCalls, hasLength(1));
      expect(s.repo.confirmCalls, hasLength(1));
      expect(s.provider.getActiveCloseRequest(_line), isNull);
      expect(_finalDialog, findsNothing);
      expect(_dialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsNothing,
      );
      await _unmount(tester, s);
    });
  });

  group('cancelled / invalidated', () {
    testWidgets('an operator cancel closes the dialog with the cancelled '
        'notice', (tester) async {
      final s = await _pump(tester, request: _waiting(), withSse: true);
      expect(_dialog, findsOneWidget);

      s.repo.activeCloseRequests.remove(_line);
      s.sse!.emit('c1', _line, 'PLAN_ITEM_CLOSE_REQUEST_CANCELLED');
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(
        _notice(PlanItemCloseRequestStrings.cancelledNotice),
        findsOneWidget,
      );
      expect(s.repo.confirmCalls, isEmpty);
      await _unmount(tester, s);
    });

    testWidgets('an invalidation removes the banner and any open final '
        'confirmation', (tester) async {
      final s = await _pump(tester, request: _completing(), withSse: true);
      await tester.tap(_bannerText(PlanItemCloseRequestStrings.bannerAction));
      await _settle(tester);
      expect(_finalDialog, findsOneWidget);

      s.repo.activeCloseRequests.remove(_line);
      s.sse!.emit('i1', _line, 'PLAN_ITEM_CLOSE_REQUEST_INVALIDATED');
      await _settle(tester);

      expect(_finalDialog, findsNothing);
      expect(
        _bannerText(PlanItemCloseRequestStrings.bannerTitle),
        findsNothing,
      );
      expect(
        _notice(PlanItemCloseRequestStrings.noLongerValidNotice),
        findsOneWidget,
      );
      expect(s.repo.confirmCalls, isEmpty);
      await _unmount(tester, s);
    });

    testWidgets('a request answered "NOT_ACTIVE" closes the dialog', (
      tester,
    ) async {
      final s = await _pump(tester, request: _waiting());
      // Confirmed from the other tablet a moment earlier.
      s.repo.activeCloseRequests.remove(_line);

      await tester.tap(_inDialog(PlanItemCloseRequestStrings.confirmAllAction));
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(
        _notice(PlanItemCloseRequestStrings.noLongerValidNotice),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('a switched-off line closes its dialog', (tester) async {
      final s = await _pump(tester, request: _waiting());

      s.serve([skewedLine(2, planItemId: 922, planProductId: 32)]);
      await s.provider.refreshBootstrap();
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(find.text('تم إيقاف الخط'), findsOneWidget);
      await tester.tap(find.text('حسناً'));
      await _settle(tester);
      await _unmount(tester, s);
    });
  });
}
