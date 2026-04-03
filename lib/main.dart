import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/di.dart';
import 'core/theme.dart';
import 'data/datasources/auth_local_storage.dart';
import 'presentation/providers/palletizing_provider.dart';
import 'presentation/providers/printing_provider.dart';
import 'presentation/screens/device_settings_screen.dart';
import 'presentation/screens/palletizing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        ChangeNotifierProvider<PrintingProvider>(
          create: (_) => serviceLocator.createPrintingProvider()..loadData(),
        ),
      ],
      child: MaterialApp(
        title: 'Taleeb ThermoForming',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const DeviceKeyWrapper(),
      ),
    );
  }
}

/// Checks if a device key is configured. If not, shows the setup screen.
/// Once configured, proceeds directly to the palletizing workflow.
class DeviceKeyWrapper extends StatefulWidget {
  const DeviceKeyWrapper({super.key});

  @override
  State<DeviceKeyWrapper> createState() => _DeviceKeyWrapperState();
}

class _DeviceKeyWrapperState extends State<DeviceKeyWrapper> {
  final _storage = AuthLocalStorage();
  bool _checking = true;
  bool _hasDeviceKey = false;

  @override
  void initState() {
    super.initState();
    _checkDeviceKey();
  }

  Future<void> _checkDeviceKey() async {
    final hasKey = await _storage.hasDeviceKey();
    if (mounted) {
      setState(() {
        _hasDeviceKey = hasKey;
        _checking = false;
      });
    }
  }

  void _onDeviceKeyConfigured() {
    setState(() {
      _hasDeviceKey = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasDeviceKey) {
      return DeviceSettingsScreen(
        isSetup: true,
        onDeviceKeyConfigured: _onDeviceKeyConfigured,
      );
    }

    return const PalletizingScreen();
  }
}
