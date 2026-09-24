import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/constants/plan_item_close_request_strings.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/palletizing_line.dart';
import '../providers/manager_announcement_notifier.dart';
import '../providers/palletizing_provider.dart';
import '../widgets/line_scoped_route.dart';
import '../widgets/plan_item_close_request_dialog.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Timer _timer;
  String _currentDateTime = '';

  /// One tab per rendered line. Recreated whenever the rendered `lineId`
  /// list changes; the selected tab is always derived from the provider's
  /// selected `lineId`, never from a stored index.
  TabController? _tabController;
  List<int> _tabLineIds = const [];

  PalletizingProvider? _provider;

  /// Guards against stacking takeover dialogs while one is already open.
  bool _takeoverDialogOpen = false;

  /// `closeRequestId` of the blocking close-request dialog on screen, or
  /// `null`. One dialog at a time, keyed by the authoritative request id.
  int? _closeRequestDialogId;

  /// "تم إيقاف الخط" dialogs still to show, one at a time.
  final List<String> _pendingSwitchedOffLabels = [];
  bool _switchedOffDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDateTime();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final palletizingProvider = context.read<PalletizingProvider>();
      _provider = palletizingProvider;
      // Show the blocking takeover dialog / line add-remove notices whenever
      // the provider flags them for any rendered line.
      palletizingProvider.addListener(_onProviderChanged);
      await palletizingProvider.loadBootstrap();
      if (!mounted) return;
      // Hand the refresh cadence to the provider's RefreshCoordinator: it owns
      // the single poll timer + the device-level SSE stream and adapts the
      // cadence to the SSE connection state. The screen only forwards
      // lifecycle signals from here on.
      palletizingProvider.startRefreshLoop();
      _onProviderChanged();
      // Bootstrap has loaded the operating lineIds — fetch any pending urgent
      // manager notice. The notifier no-ops when no lineIds are available yet.
      context.read<ManagerAnnouncementNotifier>().refresh();
    });
  }

  void _onProviderChanged() {
    if (!mounted) return;
    _drainLineNotices();
    _drainCloseRequestNotices();
    _maybeShowTakeoverDialog();
    _maybeShowCloseRequestDialog();
  }

  /// Opens the blocking [PlanItemCloseRequestDialog] for the first rendered
  /// line whose close request waits for the palletizer's decision. The
  /// provider only holds requests it read from the backend for a line with a
  /// palletizer session, so the dialog never appears before PIN login or for
  /// another line. The dialog closes itself when its request stops waiting;
  /// only then can the next one open.
  void _maybeShowCloseRequestDialog() {
    if (!mounted ||
        _closeRequestDialogId != null ||
        _takeoverDialogOpen ||
        _switchedOffDialogOpen) {
      return;
    }
    final provider = context.read<PalletizingProvider>();
    final lineId = provider.firstLineAwaitingCloseDecision();
    if (lineId == null) return;
    final closeRequestId = provider
        .getActiveCloseRequest(lineId)!
        .closeRequestId;
    _closeRequestDialogId = closeRequestId;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LineScopedRoute(
        lineId: lineId,
        child: PlanItemCloseRequestDialog(
          lineId: lineId,
          closeRequestId: closeRequestId,
          onMorePalletsRemain: () {
            if (mounted) _switchToLine(lineId);
          },
        ),
      ),
    ).whenComplete(() {
      _closeRequestDialogId = null;
      if (mounted) _onProviderChanged();
    });
  }

  /// Shows one snackbar per close request that left the screen.
  void _drainCloseRequestNotices() {
    final provider = context.read<PalletizingProvider>();
    if (!provider.hasPendingCloseRequestNotices) return;
    final multiLine = provider.renderedLineIds.length > 1;
    for (final notice in provider.takeCloseRequestNotices()) {
      final text = switch (notice.kind) {
        CloseRequestNoticeKind.confirmed =>
          PlanItemCloseRequestStrings.confirmedNotice,
        CloseRequestNoticeKind.cancelled =>
          PlanItemCloseRequestStrings.cancelledNotice,
        CloseRequestNoticeKind.noLongerValid =>
          PlanItemCloseRequestStrings.noLongerValidNotice,
      };
      _showSnack(
        multiLine ? '${provider.lineLabel(notice.lineId)}: $text' : text,
      );
    }
  }

  /// Pops the blocking [TakeoverDialog] for the first rendered line (server
  /// order) with an unacknowledged pending request. One dialog at a time — a
  /// second line's request pops after the first is dismissed.
  void _maybeShowTakeoverDialog() {
    if (!mounted ||
        _takeoverDialogOpen ||
        _switchedOffDialogOpen ||
        _closeRequestDialogId != null) {
      return;
    }
    final provider = context.read<PalletizingProvider>();
    for (final lineId in provider.renderedLineIds) {
      if (!provider.isTakeoverDialogPending(lineId)) continue;
      provider.consumeTakeoverDialogSignal(lineId);
      final takeover = provider.getTakeover(lineId);
      if (takeover == null || !takeover.status.isActive) continue;
      _takeoverDialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LineScopedRoute(
          lineId: lineId,
          child: TakeoverDialog(lineId: lineId),
        ),
      ).whenComplete(() {
        _takeoverDialogOpen = false;
        if (mounted) _onProviderChanged();
      });
      break;
    }
  }

  /// Shows the provider's line add / remove notices. A removed line that was
  /// on screen (the selected tab, or any pane) gets the blocking
  /// "تم إيقاف الخط" dialog — its own dialogs close themselves through
  /// [LineScopedRoute] — otherwise a snackbar with the same body. A new line
  /// only gets a snackbar; the selection never jumps to it.
  void _drainLineNotices() {
    final provider = context.read<PalletizingProvider>();
    if (!provider.hasPendingLineNotices) return;
    final notices = provider.takeLineNotices();

    final removedCount = notices
        .where((n) => n.change == LineAvailabilityChange.removed)
        .length;
    final addedCount = notices.length - removedCount;
    final previousCount =
        provider.renderedLineIds.length + removedCount - addedCount;
    final wasPanes = usePalletizingPanes(
      MediaQuery.sizeOf(context).width,
      previousCount,
    );

    if (addedCount > 0) {
      // Pending notices are filtered per lineId — fetch them for the new line.
      context.read<ManagerAnnouncementNotifier>().refresh();
    }

    for (final notice in notices) {
      if (notice.change == LineAvailabilityChange.added) {
        _showSnack('تمت إضافة ${notice.label}');
        continue;
      }
      final body = ApiException.lineInactiveMessage(notice.label);
      if (notice.wasSelected || wasPanes) {
        _pendingSwitchedOffLabels.add(notice.label);
      } else {
        _showSnack(body);
      }
    }
    _maybeShowSwitchedOffDialog();
  }

  void _maybeShowSwitchedOffDialog() {
    if (!mounted || _switchedOffDialogOpen) return;
    if (_pendingSwitchedOffLabels.isEmpty) return;
    final label = _pendingSwitchedOffLabels.removeAt(0);
    _switchedOffDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.power_settings_new_rounded,
              color: Colors.orange.shade800,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تم إيقاف الخط',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          ApiException.lineInactiveMessage(label),
          style: GoogleFonts.cairo(fontSize: 15, height: 1.6),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'حسناً',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      _switchedOffDialogOpen = false;
      if (!mounted) return;
      _maybeShowSwitchedOffDialog();
      _maybeShowTakeoverDialog();
      _maybeShowCloseRequestDialog();
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
          textDirection: TextDirection.rtl,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Keeps [_tabController] in step with the rendered lines. Called from
  /// build; creating a controller there is safe, and the replaced one is
  /// disposed after the frame so the outgoing TabBar can detach first.
  void _syncTabController(PalletizingProvider provider) {
    final ids = provider.renderedLineIds;
    if (_tabController != null && listEquals(ids, _tabLineIds)) return;

    final selected = provider.selectedLineId;
    final index = selected == null ? 0 : ids.indexOf(selected);
    final old = _tabController;
    old?.animation?.removeListener(_handleTabAnimation);

    _tabLineIds = List.of(ids);
    _tabController = TabController(
      length: ids.length,
      vsync: this,
      initialIndex: index < 0 ? 0 : index,
    );
    _tabController!.animation!.addListener(_handleTabAnimation);

    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  /// Swipe / tap on a tab → select that line (drives the app-bar colour).
  void _handleTabAnimation() {
    final controller = _tabController;
    if (controller == null || controller.length == 0) return;
    final index = controller.animation!.value.round().clamp(
      0,
      controller.length - 1,
    );
    if (index >= _tabLineIds.length) return;
    context.read<PalletizingProvider>().selectLine(_tabLineIds[index]);
  }

  /// "تغيير الخط" → jump to [lineId].
  void _switchToLine(int lineId) {
    context.read<PalletizingProvider>().selectLine(lineId);
    final index = _tabLineIds.indexOf(lineId);
    if (index >= 0) _tabController?.animateTo(index);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    final provider = context.read<PalletizingProvider>();
    if (state == AppLifecycleState.resumed) {
      // Resume could span a line enable / disable, a backend session end
      // (Thermoforming operator ended the shift-line) or a takeover
      // transition. The coordinator restarts the SSE stream and runs one
      // immediate silent bootstrap re-fetch internally.
      provider.resumeRefreshLoop();
      _onProviderChanged();
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
    _provider?.removeListener(_onProviderChanged);
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
    _syncTabController(provider);
    final lines = provider.renderedLines;
    // Before the first bootstrap there is nothing to count — lay out for the
    // historical two lines so the skeleton matches the common case.
    final layoutCount = lines.isEmpty ? 2 : lines.length;
    final usePanes = usePalletizingPanes(
      MediaQuery.sizeOf(context).width,
      layoutCount,
    );

    return Scaffold(
      appBar: usePanes
          ? _buildPanesAppBar()
          : _buildTabsAppBar(provider, lines),
      body: Stack(
        children: [
          _buildBody(provider, lines, usePanes),
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

  List<Widget> _appBarActions({double horizontalPadding = 0}) {
    Widget pad(Widget child) => horizontalPadding == 0
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: child,
          );
    return [
      pad(
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refreshData,
          tooltip: 'تحديث',
        ),
      ),
      pad(
        IconButton(
          icon: const Icon(Icons.print_rounded),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const ReprintByIdDialog(),
          ),
          tooltip: 'إعادة طباعة ملصق',
        ),
      ),
      pad(
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _openSettings,
          tooltip: 'الإعدادات',
        ),
      ),
    ];
  }

  PreferredSizeWidget _buildTabsAppBar(
    PalletizingProvider provider,
    List<PalletizingLine> lines,
  ) {
    final selectedId = provider.selectedLineId;
    final selected = selectedId == null ? null : provider.getLine(selectedId);
    final activeUi = selectedId == null
        ? null
        : provider.getUiState(selectedId);
    final isInactive =
        selected == null ||
        activeUi == LineUiState.waitingForThermoforming ||
        activeUi == LineUiState.blocked;
    // The app-bar colour follows the selected line; neutral grey (not the
    // line accent) while it waits for an operator or is blocked.
    final activeColor = isInactive ? kInactiveLineColor : selected.color;
    final scrollable = lines.length > 3;

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
      actions: _appBarActions(),
      bottom: lines.isEmpty
          ? null
          : TabBar(
              controller: _tabController,
              isScrollable: scrollable,
              tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              // Server order, not reversed: in RTL the first line sits on
              // the right — خط أ · خط ب · خط ج.
              tabs: [
                for (final line in lines)
                  _buildLineTab(
                    line,
                    // An open close request also needs this line's
                    // palletizer — dot only; it does not speed up polling.
                    urgent:
                        provider.hasUrgentLineState(line.lineId) ||
                        provider.getActiveCloseRequest(line.lineId) != null,
                  ),
              ],
            ),
    );
  }

  Widget _buildLineTab(PalletizingLine line, {required bool urgent}) {
    return Tab(
      key: ValueKey('line-tab-${line.lineId}'),
      height: 48,
      child: FittedBox(
        // Scale down instead of truncating — the label is never cut off.
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attention dot: amber while the line needs attention (waiting,
            // takeover, blocked, handover) so a hidden tab still signals it.
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: urgent ? const Color(0xFFFFC107) : Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              line.label,
              softWrap: false,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildPanesAppBar() {
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
      actions: _appBarActions(horizontalPadding: isTablet ? 4 : 8),
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsHubScreen()));
    if (!mounted) return;
    await _refreshData();
  }

  /// Opens Device Settings directly (used by the device-key error surface),
  /// then re-runs bootstrap so a corrected key takes effect immediately
  /// without requiring the operator to manually tap retry.
  Future<void> _openDeviceSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()));
    if (!mounted) return;
    await _refreshData();
  }

  /// Device-key recovery surface. Shown when bootstrap failed with HTTP
  /// 401 / 403 on a `/palletizing-line/*` endpoint. Distinct from the generic
  /// error screen because the recovery action is different — the operator
  /// must open Device Settings to inspect / test / replace the key, not just
  /// retry the same call against the same backend.
  Widget _buildDeviceKeyErrorScreen(PalletizingProvider provider) {
    final message =
        provider.errorMessage ?? 'مفتاح الجهاز غير صحيح أو غير مفعّل';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.key_off_rounded,
              size: 72,
              color: Colors.orange.shade700,
            ),
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
            Icon(Icons.inbox_outlined, size: 72, color: Colors.grey.shade500),
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

  Widget _buildLoadingShimmer(
    PalletizingProvider provider,
    List<PalletizingLine> lines,
    bool usePanes,
  ) {
    // Skeleton count = last known rendered count (2 before any bootstrap).
    final accents = lines.isEmpty
        ? [LineAccent.forLineNumber(1), LineAccent.forLineNumber(2)]
        : [for (final line in lines) line.accent];
    if (usePanes) return PalletizingShimmerPanes(accents: accents);

    final selectedId = provider.selectedLineId;
    final selected = selectedId == null ? null : provider.getLine(selectedId);
    return PalletizingShimmer(accent: selected?.accent ?? accents.first);
  }

  Widget _buildBody(
    PalletizingProvider provider,
    List<PalletizingLine> lines,
    bool usePanes,
  ) {
    if (provider.isLoading || provider.state == PalletizingState.idle) {
      return _buildLoadingShimmer(provider, lines, usePanes);
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

    // Bootstrap succeeded with no active line (`lines: []`) — every line is
    // switched off, or the backend response shape changed. SSE and the safety
    // bootstrap keep running, so lines come back on their own when enabled.
    if (lines.isEmpty) {
      return _buildNoLinesScreen();
    }

    if (!usePanes) {
      return TabBarView(
        controller: _tabController,
        children: [
          for (final line in lines) _buildLinePane(provider, line, tabs: true),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) Container(width: 2, color: Colors.grey.shade300),
          Expanded(child: _buildLinePane(provider, lines[i], tabs: false)),
        ],
      ],
    );
  }

  /// One line's content. Keyed by `lineId` so adding / removing a line never
  /// hands one line's widget state (PIN entry, animations) to another.
  Widget _buildLinePane(
    PalletizingProvider provider,
    PalletizingLine line, {
    required bool tabs,
  }) {
    final ui = provider.getUiState(line.lineId);
    // Neutral grey background while the line waits or is blocked.
    final background =
        (ui == LineUiState.waitingForThermoforming || ui == LineUiState.blocked)
        ? kInactiveLineBackground
        : line.lightColor;
    // Tabs only: "تغيير الخط" offers the next usable line in server order;
    // panes show every line at once.
    final switchTarget = tabs ? provider.nextUsableLineId(line.lineId) : null;

    return RefreshIndicator(
      key: ValueKey('line-pane-${line.lineId}'),
      onRefresh: _refreshData,
      child: Container(
        color: background,
        child: ProductionLineSection(
          key: ValueKey('line-section-${line.lineId}'),
          line: line,
          canSwitchLine: switchTarget != null,
          onSwitchLine: switchTarget == null
              ? null
              : () => _switchToLine(switchTarget),
        ),
      ),
    );
  }
}
