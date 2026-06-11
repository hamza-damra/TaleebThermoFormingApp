import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/config.dart';
import 'core/di.dart';
import 'core/http/staging_http_overrides.dart';
import 'core/theme.dart';
import 'presentation/providers/manager_announcement_notifier.dart';
import 'presentation/providers/palletizing_provider.dart';
import 'presentation/providers/printing_provider.dart';
import 'presentation/screens/palletizing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Install staging TLS override BEFORE any HttpClient is constructed. The
  // getter is itself triple-gated (non-production env, opt-in dart-define,
  // host on the staging whitelist) — production builds always fall through.
  if (AppConfig.allowStagingSelfSignedCert) {
    HttpOverrides.global =
        StagingSelfSignedHttpOverrides(AppConfig.stagingTlsHosts);
  }

  // Release-visible startup banner — appears in `adb logcat` even when
  // kDebugMode is false. Lets a tablet operator confirm WHICH build is running,
  // which environment it targets, and whether the staging TLS bypass is on.
  // Never logs secrets (device key, tokens, credentials).
  debugPrint(
    '[Startup] buildLabel=${AppConfig.buildLabel} '
    'appEnv=${AppConfig.envLabel()} '
    'baseUrl=${AppConfig.baseUrl} '
    'allowStagingSelfSignedCert=${AppConfig.allowStagingSelfSignedCert} '
    'mode=${kReleaseMode ? "release" : "debug"}',
  );
  await serviceLocator.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PalletizingProvider>(
          create: (_) => serviceLocator.createPalletizingProvider(),
        ),
        // Registered after PalletizingProvider so its create can read the live
        // instance for the lineId snapshot. Subscribes to the same single SSE
        // stream — no second connection.
        ChangeNotifierProvider<ManagerAnnouncementNotifier>(
          create: (context) {
            final palletizing = context.read<PalletizingProvider>();
            return serviceLocator.createManagerAnnouncementNotifier(
              lineIdsSupplier: () => palletizing.knownOperatingLineIds,
            );
          },
        ),
        ChangeNotifierProvider<PrintingProvider>(
          create: (_) => serviceLocator.createPrintingProvider()..loadData(),
        ),
      ],
      child: MaterialApp(
        title: 'مصنع طليب',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PalletizingScreen(),
      ),
    );
  }
}
