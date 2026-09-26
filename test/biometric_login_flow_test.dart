// Biometric login gate — provider and PIN-screen flow (handoff §7–§9, §11,
// §12, §14).
//   * a `BIOMETRIC_*` refusal opens the fingerprint dialog and is not a
//     wrong PIN; every other refusal keeps its inline error;
//   * after a scan the dialog completes the login with ONE re-submit of the
//     same PIN, without re-typing;
//   * Contact admin / Retry / Network / cancel each behave as specified;
//   * a refused login never touches the line's existing session, and the
//     attempt token is never persisted or logged.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taleeb_thermoforming/core/constants/biometric_login_strings.dart';
import 'package:taleeb_thermoforming/core/exceptions/api_exception.dart';
import 'package:taleeb_thermoforming/data/datasources/auth_local_storage.dart';
import 'package:taleeb_thermoforming/domain/entities/biometric_login.dart';
import 'package:taleeb_thermoforming/domain/entities/bootstrap_response.dart';
import 'package:taleeb_thermoforming/domain/entities/palletizer_auth_result.dart';
import 'package:taleeb_thermoforming/domain/repositories/biometric_login_repository.dart';
import 'package:taleeb_thermoforming/presentation/providers/manager_announcement_notifier.dart';
import 'package:taleeb_thermoforming/presentation/providers/palletizing_provider.dart';
import 'package:taleeb_thermoforming/presentation/screens/palletizing_screen.dart';
import 'package:taleeb_thermoforming/presentation/widgets/biometric_login_dialog.dart';
import 'package:taleeb_thermoforming/presentation/widgets/palletizer_pin_screen.dart';

import 'support/biometric_fakes.dart';
import 'support/google_fonts_test_harness.dart';
import 'support/line3_fakes.dart';

const _line = 11; // skewed fixture: lineNumber 1
const _secret = 'SECRET-ATTEMPT-TOKEN-7f3a';

PalletizerAuthResult _loggedIn(int lineId) =>
    PalletizerAuthResult(session: activeSession(lineId), sessionToken: 'fresh');

ApiException _api(String code, int status) => ApiException(
  code: code,
  message: 'English developer text',
  statusCode: status,
);

/// Serves [results] one per login: a [PalletizerAuthResult] is returned,
/// anything else is thrown.
PalletizerAuthResult Function(int) _logins(List<Object> results) => (_) {
  final next = results.removeAt(0);
  if (next is PalletizerAuthResult) return next;
  throw next;
};

// ─────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────

class _Provider {
  final repo = FakePalletizingRepository();
  final AuthLocalStorage auth;
  late final PalletizingProvider provider = PalletizingProvider(
    repo,
    auth,
    FakeNotifications(),
  );

  _Provider([AuthLocalStorage? auth]) : auth = auth ?? FakeAuthStorage();

  Future<void> boot({Map<int, String> storedTokens = const {}}) async {
    final lines = [skewedLine(1), skewedLine(2)];
    final byId = {for (final l in lines) l.lineId: l};
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (id) => byId[id]!;
    for (final e in storedTokens.entries) {
      await auth.savePalletizerSessionToken(e.key, e.value);
    }
    repo.sessionFn = (id) =>
        storedTokens.containsKey(id) ? activeSession(id) : null;
    await provider.loadBootstrap();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────

class _Screen {
  final FakePalletizingRepository repo;
  final FakeAuthStorage auth;
  final FakeBiometricRepository biometric;
  final PalletizingProvider provider;

  _Screen(this.repo, this.auth, this.biometric, this.provider);

  void serve(List<BootstrapLineState> lines) {
    final byId = {for (final l in lines) l.lineId: l};
    repo.bootstrapFn = () => skewedBootstrap(lines);
    repo.lineStateFn = (id) => byId[id]!;
  }
}

Future<_Screen> _pump(WidgetTester tester) async {
  installGoogleFontsTestHarness();
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = FakePalletizingRepository();
  final auth = FakeAuthStorage();
  final biometric = FakeBiometricRepository();
  final provider = PalletizingProvider(repo, auth, FakeNotifications());
  final screen = _Screen(repo, auth, biometric, provider)
    ..serve([skewedLine(1)]);
  repo.sessionFn = (id) =>
      auth.tokens.containsKey(id) ? activeSession(id) : null;
  final notifier = ManagerAnnouncementNotifier(
    repo,
    lineIdsSupplier: () => provider.knownOperatingLineIds,
  );
  addTearDown(notifier.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<BiometricLoginRepository>.value(value: biometric),
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

/// Fixed-step pumps — the PIN cursor and the dialog spinners animate
/// forever, so `pumpAndSettle` would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester, _Screen screen) async {
  await tester.pumpWidget(const SizedBox.shrink());
  screen.provider.dispose();
  await tester.pump(const Duration(seconds: 1));
}

Finder get _pinField => find.descendant(
  of: find.byType(PalletizerPinScreen),
  matching: find.byType(TextField),
);

Finder get _loginButton => find.descendant(
  of: find.byType(PalletizerPinScreen),
  matching: find.widgetWithText(ElevatedButton, 'دخول'),
);

Finder get _dialog => find.byType(BiometricLoginDialog);

Finder _dialogText(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

Future<void> _login(WidgetTester tester, [String pin = '1234']) async {
  await tester.enterText(_pinField, pin);
  await tester.tap(_loginButton);
  await _settle(tester);
}

void main() {
  group('provider', () {
    test(
      'a biometric refusal is not a PIN error and persists nothing',
      () async {
        final t = _Provider();
        await t.boot();
        t.repo.authFn = _logins([
          BiometricDenialException(denialWithToken(_secret)),
        ]);

        final outcome = await t.provider.palletizerAuthAttempt(_line, '1234');

        expect(outcome.status, PalletizerAuthStatus.biometricRequired);
        expect(outcome.denial!.attemptToken, _secret);
        expect(t.provider.getPalletizerAuthError(_line), isNull);
        expect(t.provider.getPalletizerAuthErrorCode(_line), isNull);
        expect(t.provider.isPalletizerAuthenticating(_line), isFalse);
        expect(t.provider.getUiState(_line), LineUiState.needsPalletizerAuth);
        expect((t.auth as FakeAuthStorage).tokens, isEmpty);

        // The bool API treats it as "not logged in".
        t.repo.authFn = _logins([
          BiometricDenialException(denialWithoutToken()),
        ]);
        expect(await t.provider.palletizerAuth(_line, '1234'), isFalse);
        expect(t.provider.getPalletizerAuthError(_line), isNull);
      },
    );

    test('non-biometric 403s keep their inline error', () async {
      final t = _Provider();
      await t.boot();
      t.repo.authFn = _logins([_api('PALLETIZER_NOT_ALLOWED', 403)]);

      final outcome = await t.provider.palletizerAuthAttempt(_line, '1234');

      expect(outcome.status, PalletizerAuthStatus.failed);
      expect(outcome.error!.code, 'PALLETIZER_NOT_ALLOWED');
      expect(
        t.provider.getPalletizerAuthError(_line),
        'هذا الموظف غير مصرح له بتسجيل الطبليات',
      );
    });

    test('a refused login on a line with an active palletizer leaves that '
        'session working', () async {
      final t = _Provider();
      await t.boot(storedTokens: const {_line: 'token-11'});
      expect(t.provider.hasActivePalletizerSession(_line), isTrue);
      t.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);

      final outcome = await t.provider.palletizerAuthAttempt(_line, '1234');

      expect(outcome.status, PalletizerAuthStatus.biometricRequired);
      expect(t.provider.hasActivePalletizerSession(_line), isTrue);
      expect(t.provider.getUiState(_line), LineUiState.active);
      expect(
        await t.auth.getPalletizerSessionToken(_line),
        'token-11',
        reason: 'the stored session token is untouched',
      );
    });

    test('a second login while one is in flight is dropped', () async {
      final t = _Provider();
      await t.boot();
      final gate = Completer<PalletizerAuthResult>();
      t.repo.authAsyncFn = (_) => gate.future;

      final first = t.provider.palletizerAuthAttempt(_line, '1234');
      final second = await t.provider.palletizerAuthAttempt(_line, '1234');
      expect(second.status, PalletizerAuthStatus.ignored);

      gate.complete(_loggedIn(_line));
      expect((await first).isSuccess, isTrue);
      expect(t.repo.authCalls, hasLength(1));
    });

    test('the attempt token never reaches secure storage', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final t = _Provider(AuthLocalStorage());
      await t.boot();
      t.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
        _loggedIn(_line),
      ]);

      await t.provider.palletizerAuthAttempt(_line, '1234');
      await t.provider.palletizerAuthAttempt(_line, '1234');

      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values, contains('fresh'), reason: 'the session token');
      expect(stored.values.where((v) => v.contains(_secret)), isEmpty);
      expect(stored.keys.where((k) => k.contains(_secret)), isEmpty);
    });
  });

  group('PIN screen', () {
    testWidgets('login, then scan → the dialog completes the login by itself '
        'with one re-submit of the same PIN', (tester) async {
      // Restored inside the body: testWidgets checks debug variables before
      // tear-downs run.
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await _loginThenScan(tester, logs);
      } finally {
        debugPrint = original;
      }
    });

    testWidgets('a DEVICE_UNAVAILABLE refusal opens Device offline with the '
        'server message', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(
          denialWithToken(
            _secret,
            code: BiometricCodes.deviceUnavailable,
            message: deviceMessage,
          ),
        ),
      ]);

      await _login(tester);
      expect(_dialogText(deviceMessage), findsOneWidget);
      expect(s.biometric.calls, 1, reason: 'keeps polling');

      // The terminal came back; still waiting for the scan.
      s.biometric.respond(BiometricAttemptStatus.pending);
      await _settle(tester);
      expect(_dialogText(BiometricLoginStrings.waiting), findsOneWidget);
      expect(_dialogText(deviceMessage), findsNothing);

      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);
      await _unmount(tester, s);
    });

    testWidgets('an unlinked employee → Contact admin with the server '
        'message; «حسنًا» closes it', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(
          denialWithoutToken(
            code: BiometricCodes.mappingMissing,
            message: mappingMissingMessage,
          ),
        ),
      ]);

      await _login(tester);

      expect(_dialogText(mappingMissingMessage), findsOneWidget);
      expect(_dialogText(BiometricLoginStrings.okAction), findsOneWidget);
      expect(_dialogText(BiometricLoginStrings.cancelAction), findsNothing);
      expect(_dialogText(BiometricLoginStrings.retryAction), findsNothing);
      expect(s.biometric.calls, 0);

      await tester.tap(_dialogText(BiometricLoginStrings.okAction));
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.repo.authCalls, hasLength(1), reason: 'no automatic retry');
      expect(find.byType(PalletizerPinScreen), findsOneWidget);
      await _unmount(tester, s);
    });

    testWidgets('no attempt recorded → Retry; «إعادة المحاولة» re-submits the '
        'login without re-typing', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithoutToken()),
        _loggedIn(_line),
      ]);

      await _login(tester, '2468');
      expect(_dialogText(requiredMessage), findsOneWidget);
      expect(_dialogText(BiometricLoginStrings.retryAction), findsOneWidget);
      expect(_dialogText(BiometricLoginStrings.cancelAction), findsOneWidget);
      expect(s.biometric.calls, 0);

      await tester.tap(_dialogText(BiometricLoginStrings.retryAction));
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.repo.authCalls.map((c) => c.pin), ['2468', '2468']);
      expect(s.provider.hasActivePalletizerSession(_line), isTrue);
      await _unmount(tester, s);
    });

    testWidgets('410 → Retry with the dialog text', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);
      s.biometric.answers.add(BiometricAttemptExpiredException());

      await _login(tester);

      expect(_dialogText(BiometricLoginStrings.retry), findsOneWidget);
      expect(_dialogText(BiometricLoginStrings.retryAction), findsOneWidget);
      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);
      await _unmount(tester, s);
    });

    testWidgets('a lost status call shows Network and retries after 1 s', (
      tester,
    ) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);
      s.biometric.answers.add(ApiException.network());

      await tester.enterText(_pinField, '1234');
      await tester.tap(_loginButton);
      // The dialog opens and its first poll fails: the 1 s backoff starts.
      await tester.pump();
      await tester.pump();
      expect(_dialogText(BiometricLoginStrings.network), findsOneWidget);
      expect(s.biometric.calls, 1);

      await tester.pump(const Duration(milliseconds: 900));
      expect(s.biometric.calls, 1, reason: 'still backing off');
      await tester.pump(const Duration(milliseconds: 200));
      expect(s.biometric.calls, 2);

      s.biometric.respond(BiometricAttemptStatus.pending);
      await _settle(tester);
      expect(_dialogText(BiometricLoginStrings.waiting), findsOneWidget);

      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);
      await _unmount(tester, s);
    });

    testWidgets('«إلغاء» closes the dialog, aborts the long-poll and polls '
        'no more', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);

      await _login(tester);
      expect(s.biometric.hasHeldCall, isTrue);

      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.biometric.cancelledCalls, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(s.biometric.calls, 1);
      expect(s.repo.authCalls, hasLength(1));
      expect(find.byType(PalletizerPinScreen), findsOneWidget);
      await _unmount(tester, s);
    });

    testWidgets('the PIN changed meanwhile → the dialog closes and the PIN '
        'error shows', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
        _api('OPERATOR_PIN_INVALID', 401),
      ]);
      s.biometric.answers.add(BiometricAttemptStatus.verified);

      await _login(tester);
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.repo.authCalls, hasLength(2));
      expect(
        find.descendant(
          of: find.byType(PalletizerPinScreen),
          matching: find.text('رمز المشغل غير صحيح'),
        ),
        findsOneWidget,
      );
      await _unmount(tester, s);
    });

    testWidgets('a non-biometric 403 shows the inline error and no dialog', (
      tester,
    ) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([_api('PALLETIZER_NOT_ALLOWED', 403)]);

      await _login(tester);

      expect(_dialog, findsNothing);
      expect(
        find.text('هذا الموظف غير مصرح له بتسجيل الطبليات'),
        findsOneWidget,
      );
      expect(s.biometric.calls, 0);
      await _unmount(tester, s);
    });

    testWidgets('two quick taps on «دخول» → one attempt, one dialog', (
      tester,
    ) async {
      final s = await _pump(tester);
      final gate = Completer<PalletizerAuthResult>();
      s.repo.authAsyncFn = (_) => gate.future;

      await tester.enterText(_pinField, '1234');
      await tester.tap(_loginButton);
      await tester.tap(_loginButton, warnIfMissed: false);
      gate.completeError(BiometricDenialException(denialWithToken(_secret)));
      await _settle(tester);

      expect(_dialog, findsOneWidget);
      expect(s.repo.authCalls, hasLength(1));
      expect(s.biometric.calls, 1);

      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);
      await _unmount(tester, s);
    });

    testWidgets('the dialog closes itself when the line no longer needs a '
        'palletizer login', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);
      await _login(tester);
      expect(_dialog, findsOneWidget);

      // The operator's shift ended: the line waits for an operator again.
      s.serve([skewedLine(1, waitingForOperator: true)]);
      await s.provider.refreshBootstrap();
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.biometric.cancelledCalls, 1);
      expect(s.repo.authCalls, hasLength(1));
      await _unmount(tester, s);
    });

    testWidgets('the back button acts as «إلغاء»', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);
      await _login(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(s.biometric.cancelledCalls, 1);
      await _unmount(tester, s);
    });

    testWidgets('app resume polls again at once', (tester) async {
      final s = await _pump(tester);
      s.repo.authFn = _logins([
        BiometricDenialException(denialWithToken(_secret)),
      ]);
      await _login(tester);
      expect(s.biometric.calls, 1);

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await _settle(tester);

      expect(s.biometric.cancelledCalls, 1);
      expect(s.biometric.calls, 2);
      expect(s.biometric.tokens.toSet(), {_secret});

      await tester.tap(_dialogText(BiometricLoginStrings.cancelAction));
      await _settle(tester);
      await _unmount(tester, s);
    });
  });
}

Future<void> _loginThenScan(WidgetTester tester, List<String> logs) async {
  final s = await _pump(tester);
  s.repo.authFn = _logins([
    BiometricDenialException(denialWithToken(_secret)),
    _loggedIn(_line),
  ]);

  await _login(tester, '4321');

  expect(_dialog, findsOneWidget);
  expect(_dialogText(BiometricLoginStrings.dialogTitle), findsOneWidget);
  expect(_dialogText(BiometricLoginStrings.waiting), findsOneWidget);
  expect(_dialogText(requiredMessage), findsOneWidget);
  expect(_dialogText(BiometricLoginStrings.waitingSecondary), findsOneWidget);
  expect(_dialogText(BiometricLoginStrings.cancelAction), findsOneWidget);
  expect(s.biometric.tokens, [_secret]);
  expect(s.repo.authCalls, hasLength(1));
  // Not a wrong PIN: no inline error behind the dialog, and the token is
  // never displayed.
  expect(s.provider.getPalletizerAuthError(_line), isNull);
  expect(find.textContaining(_secret), findsNothing);

  // The employee scans at the terminal.
  s.biometric.respond(BiometricAttemptStatus.verified);
  await _settle(tester);

  expect(_dialog, findsNothing);
  expect(s.repo.authCalls, [
    (lineId: _line, pin: '4321'),
    (lineId: _line, pin: '4321'),
  ]);
  expect(s.provider.hasActivePalletizerSession(_line), isTrue);
  expect(find.byType(PalletizerPinScreen), findsNothing);
  expect(s.auth.tokens, {_line: 'fresh'});
  expect(logs.where((l) => l.contains(_secret)), isEmpty);

  await _unmount(tester, s);
}
