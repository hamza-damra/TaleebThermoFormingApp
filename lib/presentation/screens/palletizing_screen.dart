import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/auth_provider.dart';
import '../providers/palletizing_provider.dart';
import '../providers/shift_handover_provider.dart';
import '../widgets/production_line_section.dart';
import '../widgets/shift_handover_dialog.dart';
import '../widgets/shimmer/palletizing_shimmer.dart';
import 'settings_hub_screen.dart';

class PalletizingScreen extends StatefulWidget {
  const PalletizingScreen({super.key});

  @override
  State<PalletizingScreen> createState() => _PalletizingScreenState();
}

class _PalletizingScreenState extends State<PalletizingScreen>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  String _currentDateTime = '';
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDateTime();
    });
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final palletizingProvider = context.read<PalletizingProvider>();
      final handoverProvider = context.read<ShiftHandoverProvider>();

      await palletizingProvider.loadInitialData();
      handoverProvider.fetchCurrentShift();
    });
  }

  void _handleTabChange() {
    if (_tabController!.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _tabController?.dispose();
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
      body: _buildBody(provider, useTabs),
    );
  }

  PreferredSizeWidget _buildAppBar(bool useTabs) {
    if (useTabs) {
      final activeColor = _tabController?.index == 1
          ? ProductionLine.line2.color
          : ProductionLine.line1.color;

      return AppBar(
        backgroundColor: activeColor,
        title: Text(
          'تكوين المشاتيح',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        toolbarHeight: 56,
        leading: IconButton(
          icon: const Icon(Icons.person),
          onPressed: () {
            // TODO: Show operator info
          },
          tooltip: 'المناوب',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
            ),
            tooltip: 'الإعدادات',
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _handleShiftHandover(context),
            tooltip: 'تسليم المناوبة',
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'خط 1',
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
                    'خط 2',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final authProvider = context.watch<AuthProvider>();
    final userName = authProvider.user?.name ?? 'المناوب';

    final isTablet = ResponsiveHelper.isTablet(context);
    final titleFontSize = isTablet ? 18.0 : 20.0;
    final dateFontSize = isTablet ? 14.0 : 16.0;

    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'تكوين المشاتيح',
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
      leading: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'المناوب: $userName',
                  style: GoogleFonts.cairo(
                    fontSize: isTablet ? 12 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      leadingWidth: isTablet ? 180 : 140,
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 4 : 8),
          child: IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
            ),
            tooltip: 'الإعدادات',
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 12),
          child: isTablet
              ? IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => _handleShiftHandover(context),
                  tooltip: 'تسليم المناوبة',
                )
              : OutlinedButton.icon(
                  onPressed: () => _handleShiftHandover(context),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: Text(
                    'تسليم المناوبة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleShiftHandover(BuildContext context) async {
    final palletizingProvider = context.read<PalletizingProvider>();
    final handoverProvider = context.read<ShiftHandoverProvider>();
    final authProvider = context.read<AuthProvider>();

    // First ask: do you have incomplete pallets to hand over?
    final hasIncomplete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        final dialogWidth = isMobile ? screenWidth * 0.9 : 400.0;
        
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: 24,
          ),
          child: Container(
            width: dialogWidth,
            constraints: BoxConstraints(maxWidth: dialogWidth),
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with close icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'تسليم المناوبة',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: Icon(Icons.close, color: Colors.grey.shade600),
                    tooltip: 'إلغاء',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'هل لديك مشاتيح غير مكتملة تريد تسليمها للمناوبة القادمة؟',
                style: GoogleFonts.cairo(fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Action buttons - always stacked vertically
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'نعم، تسليم المشاتيح',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 13 : 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'لا، خروج فقط',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 13 : 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );

    if (hasIncomplete == null || !context.mounted) return;

    if (hasIncomplete == false) {
      // Just logout, no handover needed
      await authProvider.logout();
      return;
    }

    // Show the handover dialog to declare incomplete pallets
    final selectedOperator = palletizingProvider.getSelectedOperator(
      (_tabController?.index ?? 0) + 1,
    );

    if (!context.mounted) return;

    final activeLineNumber = (_tabController?.index ?? 0) + 1;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ShiftHandoverDialog(
        productTypes: palletizingProvider.productTypes,
        productionLines: palletizingProvider.productionLines,
        operators: palletizingProvider.operators,
        initialOperator: selectedOperator,
        themeColor: activeLineNumber == 1
            ? ProductionLine.line1.color
            : ProductionLine.line2.color,
      ),
    );

    if (result == null || !context.mounted) return;

    final operatorId = result['operatorId'] as int;
    final items = result['items'] as List<Map<String, dynamic>>;

    if (items.isEmpty) return;

    // Create the handover
    final handover = await handoverProvider.createHandover(
      operatorId: operatorId,
      items: items,
    );

    if (!context.mounted) return;

    if (handover != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تسليم المناوبة بنجاح', style: GoogleFonts.cairo()),
          backgroundColor: Colors.green,
        ),
      );
      await authProvider.logout();
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

  Future<void> _refreshData() async {
    final palletizingProvider = context.read<PalletizingProvider>();
    final handoverProvider = context.read<ShiftHandoverProvider>();
    palletizingProvider.clearError();
    await palletizingProvider.loadInitialData();
    handoverProvider.fetchCurrentShift();
  }

  Widget _buildLoadingShimmer(bool isMobile) {
    if (isMobile) {
      // For mobile, show shimmer in TabBarView matching tabs
      return TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          PalletizingShimmer(line: ProductionLine.line1),
          PalletizingShimmer(line: ProductionLine.line2),
        ],
      );
    }

    // Desktop/tablet: dual pane shimmer
    return const PalletizingShimmerDualPane();
  }

  Widget _buildBody(PalletizingProvider provider, bool isMobile) {
    if (provider.isLoading) {
      return _buildLoadingShimmer(isMobile);
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

    // Find API entities matching the hardcoded lines
    final line1Entity = provider.productionLines
        .where((l) => l.lineNumber == 1)
        .firstOrNull;
    final line2Entity = provider.productionLines
        .where((l) => l.lineNumber == 2)
        .firstOrNull;

    if (isMobile) {
      return TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: ProductionLine.line1.lightColor,
              child: ProductionLineSection(
                line: ProductionLine.line1,
                productionLineEntity: line1Entity,
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: ProductionLine.line2.lightColor,
              child: ProductionLineSection(
                line: ProductionLine.line2,
                productionLineEntity: line2Entity,
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
              color: ProductionLine.line2.lightColor,
              child: ProductionLineSection(
                line: ProductionLine.line2,
                productionLineEntity: line2Entity,
              ),
            ),
          ),
        ),
        Container(width: 2, color: Colors.grey.shade300),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: Container(
              color: ProductionLine.line1.lightColor,
              child: ProductionLineSection(
                line: ProductionLine.line1,
                productionLineEntity: line1Entity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
