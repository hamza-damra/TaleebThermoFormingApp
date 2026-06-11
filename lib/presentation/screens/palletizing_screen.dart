import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/manager_announcement_notifier.dart';
import '../providers/palletizing_provider.dart';
import '../widgets/production_line_section.dart';
import '../widgets/reprint_by_id_dialog.dart';
import '../widgets/takeover_dialog.dart';
import '../widgets/urgent_announcement_overlay.dart';
import '../widgets/shimmer/palletizing_shimmer.dart';
import 'device_settings_screen.dart';
import 'settings_hub_screen.dart';

class PalletizingScreen extends StatefulWidget {
  const PalletizingScreen({super.key});

  @override
  State<PalletizingScreen> createState() => _PalletizingScreenState();
}

class _PalletizingScreenState extends State<PalletizingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Timer _timer;
  String _currentDateTime = '';
  TabController? _tabController;
  int _activeTabIndex = 0;

  /// Guards against stacking takeover dialogs while one is already open.
  bool _takeoverDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDateTime();
    });
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.animation!.addListener(_handleTabAnimation);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final palletizingProvider = context.read<PalletizingProvider>();
      // Show the blocking takeover dialog whenever the provider flags a new
      // pending request for any line.
      palletizingProvider.addListener(_maybeShowTakeoverDialog);
      await palletizingProvider.loadBootstrap();
      if (!mounted) return;
      // Hand the refresh cadence to the provider's RefreshCoordinator: it owns
      // the single poll timer + the device-level SSE stream and adapts the
      // cadence to the SSE connection state. The screen only forwards
      // lifecycle signals from here on.
      palletizingProvider.startRefreshLoop();
      _maybeShowTakeoverDialog();
      // Bootstrap has loaded the operating lineIds — fetch any pending urgent
      // manager notice. The notifier no-ops when no lineIds are available yet.
      context.read<ManagerAnnouncementNotifier>().refresh();
    });
  }

  /// Pops the blocking [TakeoverDialog] for the first line with an
  /// unacknowledged pending request. One dialog at a time — a second line's
  /// request pops after the first is dismissed.
  void _maybeShowTakeoverDialog() {
    if (!mounted || _takeoverDialogOpen) return;
    final provider = context.read<PalletizingProvider>();
    for (final n in const [1, 2]) {
      if (!provider.isTakeoverDialogPending(n)) continue;
      provider.consumeTakeoverDialogSignal(n);
      final takeover = provider.getTakeover(n);
      if (takeover == null || !takeover.status.isActive) continue;
      _takeoverDialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TakeoverDialog(lineNumber: n),
      ).whenComplete(() {
        _takeoverDialogOpen = false;
        if (mounted) _maybeShowTakeoverDialog();
      });
      break;
    }
  }

  void _handleTabAnimation() {
    final newIndex = (_tabController!.animation!.value).round();
    if (newIndex != _activeTabIndex) {
      setState(() {
        _activeTabIndex = newIndex;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    final provider = context.read<PalletizingProvider>();
    if (state == AppLifecycleState.resumed) {
      // Resume could span a backend session end (Thermoforming operator
      // ended the shift-line) or a takeover transition. The coordinator
      // restarts the SSE stream and runs one immediate refresh internally.
      provider.resumeRefreshLoop();
      _maybeShowTakeoverDialog();
      // A notice may have arrived (or been acked elsewhere) while backgrounded;
      // re-fetch the authoritative pending list on resume.
      context.read<ManagerAnnouncementNotifier>().refresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Stop the poll timer + SSE stream while backgrounded — resume restarts
      // them. Never leave a timer or socket running off-screen.
      provider.pauseRefreshLoop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _tabController?.animation?.removeListener(_handleTabAnimation);
    _tabController?.dispose();
    // The provider may outlive this screen — drop our listener explicitly.
    try {
      context.read<PalletizingProvider>().removeListener(
        _maybeShowTakeoverDialog,
      );
    } catch (_) {}
    super.dispose();
  }

  void _updateDateTime() {
    final now = DateTime.now();
    final arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final day = now.day;
    final month = arabicMonths[now.month - 1];
    final year = now.year;
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'مساءً' : 'صباحاً';

    setState(() {
      _currentDateTime = '$day $month $year , $hour:$minute $period';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final useTabs =
        ResponsiveHelper.isMobile(context) ||
        ResponsiveHelper.isTablet(context);

    return Scaffold(
      appBar: _buildAppBar(useTabs),
      body: Stack(
        children: [
          _buildBody(provider, useTabs),
          // Global blocking notice, layered above every machine tab / sub-flow.
          // Only mounted while a sanitized urgent announcement is pending; the
          // Consumer scopes rebuilds to this overlay.
          Consumer<ManagerAnnouncementNotifier>(
            builder: (_, announcements, _) => announcements.current == null
                ? const SizedBox.shrink()
                : const UrgentAnnouncementOverlay(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool useTabs) {
    if (useTabs) {
      final provider = context.watch<PalletizingProvider>();
      final activeLineNumber = _activeTabIndex == 1 ? 2 : 1;
      final activeUi = provider.getUiState(activeLineNumber);
      final isInactive =
          activeUi == LineUiState.waitingForThermoforming ||
          activeUi == LineUiState.blocked;

      final activeColor = isInactive
          ? const Color(0xFF78909C) // blue-grey 400 — neutral, not green
          : (_activeTabIndex == 1
              ? ProductionLine.line2.color
              : ProductionLine.line1.color);

      return AppBar(
        backgroundColor: activeColor,
        title: Text(
          'تكوين طبليات',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        toolbarHeight: 56,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshData,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ReprintByIdDialog(),
            ),
            tooltip: 'إعادة طباعة ملصق',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'الإعدادات',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ماكنة 1',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ماكنة 2',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isTablet = ResponsiveHelper.isTablet(context);
    final titleFontSize = isTablet ? 18.0 : 20.0;
    final dateFontSize = isTablet ? 14.0 : 16.0;

    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'تكوين طبليات',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _currentDateTime,
              style: GoogleFonts.cairo(
                fontSize: dateFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      centerTitle: true,
      toolbarHeight: 60,
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 4 : 8),
          child: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshData,
            tooltip: 'تحديث',
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 4 : 8),
          child: IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ReprintByIdDialog(),
            ),
            tooltip: 'إعادة طباعة ملصق',
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 4 : 8),
          child: IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'الإعدادات',
          ),
        ),
      ],
    );
  }

  Future<void> _refreshData() async {
    final palletizingProvider = context.read<PalletizingProvider>();
    palletizingProvider.clearError();
    await palletizingProvider.loadBootstrap();
  }

  /// Opens the Settings hub and force-refreshes bootstrap on return.
  /// Settings can change the device key (or test it), and operators routinely
  /// open this when something looks stuck — a fresh bootstrap on dismiss is
  /// the cheap recovery path so the screen never relies on cached state.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
    );
    if (!mounted) return;
    await _refreshData();
  }

  /// Opens Device Settings directly (used by the device-key error surface),
  /// then re-runs bootstrap so a corrected key takes effect immediately
  /// without requiring the operator to manually tap retry.
  Future<void> _openDeviceSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()),
    );
    if (!mounted) return;
    await _refreshData();
  }

  /// Device-key recovery surface. Shown when bootstrap failed with HTTP
  /// 401 / 403 on a `/palletizing-line/*` endpoint. Distinct from the generic
  /// error screen because the recovery action is different — the operator
  /// must open Device Settings to inspect / test / replace the key, not just
  /// retry the same call against the same backend.
  Widget _buildDeviceKeyErrorScreen(PalletizingProvider provider) {
    final message = provider.errorMessage ?? 'مفتاح الجهاز غير صحيح أو غير مفعّل';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key_off_rounded, size: 72, color: Colors.orange.shade700),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Text(
              'تعذّر التحقق من هذا الجهاز لدى الخادم. '
              'افتح إعدادات الجهاز للتحقق من المفتاح أو تواصل مع الإدارة.',
              style: GoogleFonts.cairo(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.7,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _openDeviceSettings,
              icon: const Icon(Icons.settings_input_component_rounded),
              label: Text(
                'إعدادات الجهاز',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'إعادة المحاولة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty-state surface when bootstrap succeeded but no production lines
  /// were parsed. Distinct from the device-key error and the generic
  /// retry-error screens because the recovery action is the same as the
  /// shape mismatch — try again — but the *explanation* is different.
  Widget _buildNoLinesScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 72,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 20),
            Text(
              'لا توجد خطوط إنتاج متاحة',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Text(
              'تم الاتصال بالخادم لكن لم يتم استرجاع أي خط إنتاج. '
              'تأكد من إعداد خطوط الإنتاج على الخادم ثم اضغط تحديث.',
              style: GoogleFonts.cairo(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.7,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'تحديث',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _openDeviceSettings,
              icon: const Icon(Icons.settings_input_component_rounded),
              label: Text(
                'إعدادات الجهاز',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer(bool isMobile) {
    if (isMobile) {
      return TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          PalletizingShimmer(line: ProductionLine.line1),
          PalletizingShimmer(line: ProductionLine.line2),
        ],
      );
    }

    return const PalletizingShimmerDualPane();
  }

  Widget _buildBody(PalletizingProvider provider, bool isMobile) {
    if (provider.isLoading || provider.state == PalletizingState.idle) {
      return _buildLoadingShimmer(isMobile);
    }

    // Dedicated device-key recovery surface — never reused for transient
    // errors. The CTA opens Device Settings (where the operator/admin can
    // re-test the key) instead of a generic "retry" loop that would just
    // re-hit the same 401 response.
    if (provider.isDeviceKeyInvalid) {
      return _buildDeviceKeyErrorScreen(provider);
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              provider.errorMessage!,
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.red.shade700,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshData,
              child: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      );
    }

    // Defensive empty-state. Bootstrap succeeded but parsed zero lines —
    // either the backend response shape changed (now caught by
    // BootstrapResponseModel which accepts both `lines` and `lineStates`) or
    // the backend genuinely returned no lines. The previous build silently
    // rendered two "no operator" overlays here, which read on the floor as
    // "the app is broken / no production lines available" with no actionable
    // explanation. This surface tells the operator exactly what happened and
    // provides a direct refresh path; raw diagnostics are in the debug log
    // (`[Bootstrap RAW]` / `[Bootstrap PARSE]`).
    if (provider.productionLines.isEmpty) {
      return _buildNoLinesScreen();
    }

    final line1Entity = provider.productionLines
        .where((l) => l.lineNumber == 1)
        .firstOrNull;
    final line2Entity = provider.productionLines
        .where((l) => l.lineNumber == 2)
        .firstOrNull;

    // Determine if each line can offer a "switch" action (only useful when
    // there are two lines and the *other* one is not also blocked).
    final line1Ui = provider.getUiState(1);
    final line2Ui = provider.getUiState(2);
    final line1Active = line1Ui == LineUiState.active ||
        line1Ui == LineUiState.needsPalletizerAuth;
    final line2Active = line2Ui == LineUiState.active ||
        line2Ui == LineUiState.needsPalletizerAuth;

    // Background colour: neutral grey when the line is in an inactive state.
    Color bgFor(LineUiState ui, ProductionLine line) =>
        (ui == LineUiState.waitingForThermoforming ||
                ui == LineUiState.blocked)
            ? const Color(0xFFF5F5F5)
            : line.lightColor;

    if (isMobile) {
      return TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: bgFor(line1Ui, ProductionLine.line1),
              child: ProductionLineSection(
                line: ProductionLine.line1,
                productionLineEntity: line1Entity,
                canSwitchLine: line2Active,
                onSwitchLine: line2Active
                    ? () => _tabController?.animateTo(1)
                    : null,
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: bgFor(line2Ui, ProductionLine.line2),
              child: ProductionLineSection(
                line: ProductionLine.line2,
                productionLineEntity: line2Entity,
                canSwitchLine: line1Active,
                onSwitchLine: line1Active
                    ? () => _tabController?.animateTo(0)
                    : null,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: bgFor(line1Ui, ProductionLine.line1),
              child: ProductionLineSection(
                line: ProductionLine.line1,
                productionLineEntity: line1Entity,
                // Desktop dual-pane: no tab switching — both lines are visible.
              ),
            ),
          ),
        ),
        Container(width: 2, color: Colors.grey.shade300),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: bgFor(line2Ui, ProductionLine.line2),
              child: ProductionLineSection(
                line: ProductionLine.line2,
                productionLineEntity: line2Entity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
