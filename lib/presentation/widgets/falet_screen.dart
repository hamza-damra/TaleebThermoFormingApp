import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/product_type.dart';
import '../providers/palletizing_provider.dart';
import 'convert_falet_to_pallet_dialog.dart';
import 'dispose_falet_dialog.dart';
import 'pallet_success_dialog.dart';

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
              onRefresh: () =>
                  provider.fetchFaletItems(widget.line.number),
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
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
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

  Widget _buildFaletCard(
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

            // Quantity and timestamps
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
            SizedBox(height: isMobile ? 12 : 14),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleConvertToPallet(context, item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.line.color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      size: isMobile ? 18 : 20,
                    ),
                    label: Text(
                      'تحويل لطبلية',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 8 : 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleDispose(context, item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade300),
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: isMobile ? 18 : 20,
                    ),
                    label: Text(
                      'إتلاف',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _handleConvertToPallet(
    BuildContext context,
    FaletItem item,
  ) async {
    final provider = context.read<PalletizingProvider>();

    final freshQty = await ConvertFaletToPalletDialog.show(
      context: context,
      faletItem: item,
      themeColor: widget.line.color,
    );

    if (freshQty == null || !context.mounted) return;

    try {
      final response = await provider.convertFaletToPallet(
        lineNumber: widget.line.number,
        faletId: item.faletId,
        additionalFreshQuantity: freshQty,
      );

      if (response != null && context.mounted) {
        showDialog(
          context: context,
          builder: (context) => PalletSuccessDialog(
            pallet: response.pallet,
            lineColor: widget.line.color,
            lineNumber: widget.line.number,
          ),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDispose(
    BuildContext context,
    FaletItem item,
  ) async {
    final provider = context.read<PalletizingProvider>();

    final reason = await DisposeFaletDialog.show(
      context: context,
      faletItem: item,
      themeColor: widget.line.color,
    );

    if (reason == null || !context.mounted) return;

    try {
      await provider.disposeFalet(
        lineNumber: widget.line.number,
        faletId: item.faletId,
        reason: reason.isEmpty ? null : reason,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إتلاف الفالت بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
