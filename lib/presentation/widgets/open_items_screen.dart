import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/loose_balance_item.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/received_incomplete_pallet.dart';
import '../providers/palletizing_provider.dart';
import 'complete_incomplete_pallet_dialog.dart';
import 'pallet_success_dialog.dart';
import 'produce_pallet_from_loose_dialog.dart';

class OpenItemsScreen extends StatefulWidget {
  final ProductionLine line;

  const OpenItemsScreen({super.key, required this.line});

  static Future<void> show({
    required BuildContext context,
    required ProductionLine line,
  }) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OpenItemsScreen(line: line)));
  }

  @override
  State<OpenItemsScreen> createState() => _OpenItemsScreenState();
}

class _OpenItemsScreenState extends State<OpenItemsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PalletizingProvider>().fetchOpenItems(widget.line.number);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final isLoading = provider.isOpenItemsLoading(widget.line.number);
    final openItems = provider.getOpenItems(widget.line.number);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.line.color,
        title: Text(
          'غير مكتمل',
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
      body: isLoading && openItems == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => provider.fetchOpenItems(widget.line.number),
              child: _buildBody(context, provider, openItems, isMobile),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PalletizingProvider provider,
    dynamic openItems,
    bool isMobile,
  ) {
    final horizontalPadding = isMobile ? 16.0 : 24.0;

    if (openItems == null || openItems.isEmpty) {
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
        // Loose Balances section
        if (openItems.looseBalances.isNotEmpty) ...[
          _buildSectionHeader(
            icon: Icons.inventory_2_outlined,
            title: 'العبوات الفالتة',
            count: openItems.looseBalances.length,
            color: widget.line.color,
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 12 : 16),
          ...openItems.looseBalances.map<Widget>(
            (LooseBalanceItem item) => Padding(
              padding: EdgeInsets.only(bottom: isMobile ? 10 : 14),
              child: _buildLooseBalanceCard(context, item, isMobile),
            ),
          ),
          SizedBox(height: isMobile ? 20 : 28),
        ],

        // Received Incomplete Pallet section
        if (openItems.receivedIncompletePallet != null) ...[
          _buildSectionHeader(
            icon: Icons.pending_actions_rounded,
            title: 'طبلية ناقصة مستلمة',
            count: 1,
            color: Colors.purple.shade600,
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 12 : 16),
          _buildIncompletePalletCard(
            context,
            openItems.receivedIncompletePallet!,
            isMobile,
          ),
        ],
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
            'لا توجد عناصر غير مكتملة',
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

  Widget _buildLooseBalanceCard(
    BuildContext context,
    LooseBalanceItem item,
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
            // Product name and origin badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    ProductType.formatCompactName(item.productTypeName),
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildOriginBadge(item, isMobile),
              ],
            ),
            SizedBox(height: isMobile ? 10 : 14),

            // Count and action
            Row(
              children: [
                // Count
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
                        '${item.loosePackageCount} عبوة',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: widget.line.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Produce Pallet button
                ElevatedButton.icon(
                  onPressed: () => _handleProducePallet(context, item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.line.color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 18,
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
                    'إنشاء طبلية',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.bold,
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

  Widget _buildOriginBadge(LooseBalanceItem item, bool isMobile) {
    final isHandover = item.isFromHandover;
    final color = isHandover ? Colors.orange : Colors.green;
    final label = isHandover ? 'من تسليم' : 'الجلسة الحالية';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: color.shade700,
        ),
      ),
    );
  }

  Widget _buildIncompletePalletCard(
    BuildContext context,
    ReceivedIncompletePallet pallet,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.pending_actions_rounded,
                    color: Colors.purple.shade600,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ProductType.formatCompactName(pallet.productTypeName),
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'طبلية ناقصة — ${pallet.quantity} عبوة',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 13 : 14,
                          color: Colors.purple.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),

            // Info row
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildDetailItem(
                      'المصدر',
                      'تسليم #${pallet.sourceHandoverId}',
                      isMobile,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: isMobile ? 30 : 36,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _buildDetailItem(
                      'تاريخ الاستلام',
                      pallet.receivedAtDisplay.isNotEmpty
                          ? pallet.receivedAtDisplay
                          : '—',
                      isMobile,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 14 : 18),

            // Complete button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleCompletePallet(context, pallet),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  Icons.check_circle_outline_rounded,
                  size: isMobile ? 20 : 22,
                ),
                label: Text(
                  'إكمال الطبلية',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, bool isMobile) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 11 : 12,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: isMobile ? 2 : 4),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 13 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _handleProducePallet(
    BuildContext context,
    LooseBalanceItem item,
  ) async {
    final provider = context.read<PalletizingProvider>();

    // Find the matching product type to get packageQuantity
    final productType = provider.productTypes
        .where((pt) => pt.id == item.productTypeId)
        .firstOrNull;
    final packageQuantity = productType?.packageQuantity ?? 0;

    final result = await ProducePalletFromLooseDialog.show(
      context: context,
      looseBalance: item,
      packageQuantity: packageQuantity,
      themeColor: widget.line.color,
    );

    if (result == null || !context.mounted) return;

    try {
      final response = await provider.producePalletFromLoose(
        lineNumber: widget.line.number,
        productTypeId: item.productTypeId,
        looseQuantityToUse: result['looseQuantityToUse']!,
        freshQuantityToAdd: result['freshQuantityToAdd']!,
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

  Future<void> _handleCompletePallet(
    BuildContext context,
    ReceivedIncompletePallet pallet,
  ) async {
    final provider = context.read<PalletizingProvider>();

    final freshQty = await CompleteIncompletePalletDialog.show(
      context: context,
      incompletePallet: pallet,
      themeColor: widget.line.color,
    );

    if (freshQty == null || !context.mounted) return;

    try {
      final response = await provider.completeIncompletePallet(
        lineNumber: widget.line.number,
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
}
