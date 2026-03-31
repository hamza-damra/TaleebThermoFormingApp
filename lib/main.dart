import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'core/di.dart';
import 'core/theme.dart';
import 'domain/entities/operator.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/palletizing_provider.dart';
import 'presentation/providers/printing_provider.dart';
import 'presentation/providers/shift_handover_provider.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/palletizing_screen.dart';
import 'presentation/widgets/pending_handover_dialog.dart';

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
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => serviceLocator.createAuthProvider(),
        ),
        ChangeNotifierProvider<PalletizingProvider>(
          create: (_) => serviceLocator.createPalletizingProvider(),
        ),
        ChangeNotifierProvider<PrintingProvider>(
          create: (_) => serviceLocator.createPrintingProvider()..loadData(),
        ),
        ChangeNotifierProvider<ShiftHandoverProvider>(
          create: (_) => serviceLocator.createShiftHandoverProvider(),
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
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _handoverCheckTriggered = false;
  List<Operator> _operators = [];
  bool _isLoadingOperators = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkAuthStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isAuthenticated) {
        context.read<ShiftHandoverProvider>().checkPendingHandover();
        _loadOperators();
      }
    }
  }

  Future<void> _loadOperators() async {
    if (_isLoadingOperators) return;
    setState(() => _isLoadingOperators = true);
    try {
      final palletizingProvider = context.read<PalletizingProvider>();
      if (palletizingProvider.operators.isNotEmpty) {
        setState(() {
          _operators = palletizingProvider.operators;
          _isLoadingOperators = false;
        });
        return;
      }
      await palletizingProvider.loadInitialData();
      if (!mounted) return;
      setState(() {
        _operators = palletizingProvider.operators;
        _isLoadingOperators = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOperators = false);
    }
  }

  void _triggerHandoverCheck(AuthState authState) {
    if (authState == AuthState.authenticated && !_handoverCheckTriggered) {
      _handoverCheckTriggered = true;
      final handoverProvider = context.read<ShiftHandoverProvider>();
      handoverProvider.prepareForPendingCheck();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ShiftHandoverProvider>().checkPendingHandover();
        _loadOperators();
      });
    } else if (authState == AuthState.unauthenticated ||
        authState == AuthState.error) {
      if (_handoverCheckTriggered) {
        _handoverCheckTriggered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ShiftHandoverProvider>().clearPendingHandover();
        });
      }
    }
  }

  Future<void> _handleConfirm(
    ShiftHandoverProvider handoverProvider,
    int handoverId,
    int operatorId,
  ) async {
    final result = await handoverProvider.confirmHandover(
      id: handoverId,
      incomingOperatorId: operatorId,
    );
    if (!mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تأكيد استلام المناوبة بنجاح',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else if (handoverProvider.errorCode == 'HANDOVER_ALREADY_RESOLVED') {
      handoverProvider.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم معالجة هذا التسليم', style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange,
        ),
      );
      await handoverProvider.checkPendingHandover();
    } else if (handoverProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            handoverProvider.errorMessage!,
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      handoverProvider.clearError();
    }
  }

  Future<void> _handleReject(
    ShiftHandoverProvider handoverProvider,
    int handoverId,
    int operatorId,
  ) async {
    final result = await handoverProvider.rejectHandover(
      id: handoverId,
      incomingOperatorId: operatorId,
    );
    if (!mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم رفض التسليم وإرساله للإدارة',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (handoverProvider.errorCode == 'HANDOVER_ALREADY_RESOLVED') {
      handoverProvider.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم معالجة هذا التسليم', style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange,
        ),
      );
      await handoverProvider.checkPendingHandover();
    } else if (handoverProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            handoverProvider.errorMessage!,
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      handoverProvider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, ShiftHandoverProvider>(
      builder: (context, authProvider, handoverProvider, _) {
        _triggerHandoverCheck(authProvider.state);

        switch (authProvider.state) {
          case AuthState.initial:
          case AuthState.loading:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthState.unauthenticated:
          case AuthState.error:
            return const LoginScreen();
          case AuthState.authenticated:
            final currentUser = authProvider.user;

            if (handoverProvider.pendingCheckLoading &&
                handoverProvider.pendingHandover == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'جاري التحقق من تسليمات المناوبة...',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (handoverProvider.pendingCheckFailed &&
                handoverProvider.pendingHandover == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 64,
                        color: Colors.red.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'فشل التحقق من تسليمات المناوبة',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تأكد من الاتصال بالشبكة وحاول مرة أخرى',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          handoverProvider.checkPendingHandover();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          'إعادة المحاولة',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (handoverProvider.hasBlockingHandover) {
              final handover = handoverProvider.pendingHandover!;
              return Scaffold(
                body: Stack(
                  children: [
                    const PalletizingScreen(),
                    ModalBarrier(dismissible: false, color: Colors.black54),
                    Center(
                      child: PendingHandoverDialog(
                        handover: handover,
                        operators: _operators,
                        isLoadingOperators: _isLoadingOperators,
                        isProcessing: handoverProvider.isConfirming,
                        onConfirm:
                            currentUser == null || handoverProvider.isConfirming
                            ? null
                            : (operatorId) => _handleConfirm(
                                handoverProvider,
                                handover.id,
                                operatorId,
                              ),
                        onReject:
                            currentUser == null || handoverProvider.isConfirming
                            ? null
                            : (operatorId) => _handleReject(
                                handoverProvider,
                                handover.id,
                                operatorId,
                              ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return const PalletizingScreen();
        }
      },
    );
  }
}
