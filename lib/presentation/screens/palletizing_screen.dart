import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';
import '../widgets/production_line_section.dart';
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
      await palletizingProvider.loadBootstrap();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
            ),
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
      ],
    );
  }

  Future<void> _refreshData() async {
    final palletizingProvider = context.read<PalletizingProvider>();
    palletizingProvider.clearError();
    await palletizingProvider.loadBootstrap();
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
