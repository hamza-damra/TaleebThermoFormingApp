import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/product_type.dart';
import '../providers/palletizing_provider.dart';

class FaletScreen extends StatefulWidget {
  final ProductionLine line;

  const FaletScreen({super.key, required this.line});

  static Future<void> show({
    required BuildContext context,
    required ProductionLine line,
  }) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FaletScreen(line: line)));
  }

  @override
  State<FaletScreen> createState() => _FaletScreenState();
}

class _FaletScreenState extends State<FaletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PalletizingProvider>().fetchFaletItems(widget.line.number);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final isLoading = provider.isFaletItemsLoading(widget.line.number);
    final faletResponse = provider.getFaletItems(widget.line.number);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.line.color,
        title: Text(
          'الفالت',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 20,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      backgroundColor: widget.line.lightColor,
      body: isLoading && faletResponse == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => provider.fetchFaletItems(widget.line.number),
              child: _buildBody(context, faletResponse, isMobile),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    dynamic faletResponse,
    bool isMobile,
  ) {
    final horizontalPadding = isMobile ? 16.0 : 24.0;

    if (faletResponse == null || faletResponse.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: isMobile ? 20 : 28,
        ),
        children: [
          _buildReadOnlyPointerCard(isMobile),
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          _buildEmptyState(isMobile),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: isMobile ? 20 : 28,
      ),
      children: [
        _buildReadOnlyPointerCard(isMobile),
        SizedBox(height: isMobile ? 16 : 20),
        _buildSectionHeader(
          icon: Icons.warning_amber_rounded,
          title: 'عناصر الفالت المفتوحة',
          count: faletResponse.faletItems.length,
          color: widget.line.color,
          isMobile: isMobile,
        ),
        SizedBox(height: isMobile ? 12 : 16),
        ...faletResponse.faletItems.map<Widget>(
          (FaletItem item) => Padding(
            padding: EdgeInsets.only(bottom: isMobile ? 10 : 14),
            child: _buildFaletCard(context, item, isMobile),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyPointerCard(bool isMobile) {
    final accent = widget.line.color;
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: accent,
              size: isMobile ? 18 : 22,
            ),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الفالت يُدار من تطبيق التشكيل الحراري',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                SizedBox(height: isMobile ? 4 : 6),
                Text(
                  'لمعالجة الفالت تواصل مع المشغّل',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 12 : 14,
                    color: Colors.grey.shade700,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 20 : 28),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: isMobile ? 56 : 72,
              color: Colors.grey.shade400,
            ),
          ),
          SizedBox(height: isMobile ? 16 : 24),
          Text(
            'لا توجد عناصر فالت',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          SizedBox(height: isMobile ? 6 : 10),
          Text(
            'جميع العناصر تمت معالجتها',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required bool isMobile,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 8 : 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: isMobile ? 20 : 24),
        ),
        SizedBox(width: isMobile ? 10 : 14),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 17 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10 : 14,
            vertical: isMobile ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaletCard(BuildContext context, FaletItem item, bool isMobile) {
    if (item.managerResolved) {
      return _buildManagerResolvedCard(context, item, isMobile);
    }
    return _buildOrdinaryFaletCard(context, item, isMobile);
  }

  Widget _buildManagerResolvedCard(
    BuildContext context,
    FaletItem item,
    bool isMobile,
  ) {
    final accentColor = Colors.deepPurple;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        border: Border.all(color: accentColor.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Manager-resolved header badge
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 18,
              vertical: isMobile ? 10 : 12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.shade600, accentColor.shade400],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isMobile ? 12.5 : 16.5),
                topRight: Radius.circular(isMobile ? 12.5 : 16.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: isMobile ? 20 : 24,
                ),
                SizedBox(width: isMobile ? 8 : 10),
                Expanded(
                  child: Text(
                    'فالت معالج من المدير',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Instruction message
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isMobile ? 10 : 12),
                  decoration: BoxDecoration(
                    color: accentColor.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentColor.shade200),
                  ),
                  child: Text(
                    'هذه الكمية تم اعتمادها للإنتاج بقرار من المدير',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.w600,
                      color: accentColor.shade800,
                    ),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                SizedBox(height: isMobile ? 10 : 12),

                // Product name
                Text(
                  ProductType.formatCompactName(item.productTypeName),
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: isMobile ? 8 : 10),

                // Quantity + source operator
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 14 : 18,
                        vertical: isMobile ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_outlined,
                            size: isMobile ? 16 : 18,
                            color: accentColor,
                          ),
                          SizedBox(width: isMobile ? 6 : 8),
                          Text(
                            '${item.quantity} عبوة',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 15 : 17,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Source operator
                if (item.sourceOperatorName != null) ...[
                  SizedBox(height: isMobile ? 8 : 10),
                  _buildInfoChip(
                    icon: Icons.person_outline_rounded,
                    label: 'المشغل المصدر',
                    value: item.sourceOperatorName!,
                    color: accentColor,
                    isMobile: isMobile,
                  ),
                ],

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdinaryFaletCard(
    BuildContext context,
    FaletItem item,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product name
            Text(
              ProductType.formatCompactName(item.productTypeName),
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 10),

            // Quantity
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 18,
                    vertical: isMobile ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.line.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_outlined,
                        size: isMobile ? 16 : 18,
                        color: widget.line.color,
                      ),
                      SizedBox(width: isMobile ? 6 : 8),
                      Text(
                        '${item.quantity} عبوة',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: widget.line.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Source operator
            if (item.sourceOperatorName != null) ...[
              SizedBox(height: isMobile ? 8 : 10),
              _buildInfoChip(
                icon: Icons.person_outline_rounded,
                label: 'المشغل المصدر',
                value: item.sourceOperatorName!,
                color: widget.line.color,
                isMobile: isMobile,
              ),
            ],

            // Origin type label
            if (item.originType != null) ...[
              SizedBox(height: isMobile ? 6 : 8),
              _buildInfoChip(
                icon: Icons.label_outline_rounded,
                label: 'المصدر',
                value: _originTypeLabel(item.originType!),
                color: widget.line.color,
                isMobile: isMobile,
              ),
            ],

            // Timestamps
            if (item.createdAtDisplay != null ||
                item.updatedAtDisplay != null) ...[
              SizedBox(height: isMobile ? 8 : 10),
              Container(
                padding: EdgeInsets.all(isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    if (item.createdAtDisplay != null)
                      _buildTimestampRow(
                        'تاريخ الإنشاء',
                        item.createdAtDisplay!,
                        isMobile,
                      ),
                    if (item.updatedAtDisplay != null)
                      _buildTimestampRow(
                        'آخر تحديث',
                        item.updatedAtDisplay!,
                        isMobile,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: isMobile ? 14 : 16, color: color),
          SizedBox(width: isMobile ? 6 : 8),
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11 : 13,
              color: Colors.grey.shade600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _originTypeLabel(String originType) {
    switch (originType) {
      case 'PRODUCT_SWITCH':
        return 'تبديل منتج';
      case 'HANDOVER_LAST_ACTIVE':
        return 'تسليم آخر منتج';
      case 'RECEIVED_FROM_HANDOVER':
        return 'مستلم من التسليم';
      case 'DISPUTE_RELEASE':
        return 'إفراج نزاع';
      case 'UNDECLARED_AT_HANDOVER':
        return 'غير مصرح عند التسليم';
      default:
        return originType;
    }
  }

  Widget _buildTimestampRow(String label, String value, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 2 : 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11 : 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

}
