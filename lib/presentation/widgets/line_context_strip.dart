import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// State C top context strip for a single line. Three read-only identity rows
/// in the existing card style: operator on duty (المشغّل), palletizer using
/// this device (المُشَتِّح — with a small logout icon), and current product
/// (المنتج الحالي — read-only with the "managed by Thermoforming app" hint).
class LineContextStrip extends StatelessWidget {
  final ProductionLine line;

  const LineContextStrip({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final operator = provider.getAuthorizedOperator(line.number);
    final palletizerName = provider.getPalletizerName(line.number);
    final productType = provider.getSelectedProductType(line.number);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIdentityRow(
          context: context,
          isMobile: isMobile,
          icon: Icons.person_outline_rounded,
          label: 'المشغّل',
          value: operator?.displayLabel ?? '—',
          hasValue: operator != null,
        ),
        SizedBox(height: isMobile ? 16 : 20),
        _buildPalletizerRow(
          context: context,
          isMobile: isMobile,
          palletizerName: palletizerName,
        ),
        SizedBox(height: isMobile ? 16 : 20),
        _buildProductRow(
          context: context,
          isMobile: isMobile,
          productName: productType?.productName,
        ),
      ],
    );
  }

  Widget _buildLabelRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isMobile,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 6 : 8),
          decoration: BoxDecoration(
            color: line.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: line.color, size: isMobile ? 18 : 22),
        ),
        SizedBox(width: isMobile ? 10 : 12),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 15 : 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityRow({
    required BuildContext context,
    required bool isMobile,
    required IconData icon,
    required String label,
    required String value,
    required bool hasValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(context, icon: icon, label: label, isMobile: isMobile),
        SizedBox(height: isMobile ? 12 : 14),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 20,
            vertical: isMobile ? 14 : 18,
          ),
          decoration: BoxDecoration(
            color: hasValue
                ? line.color.withValues(alpha: 0.05)
                : Colors.grey.shade50,
            border: Border.all(
              color: hasValue
                  ? line.color.withValues(alpha: 0.3)
                  : Colors.grey.shade200,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 10 : 12,
                height: isMobile ? 10 : 12,
                decoration: BoxDecoration(
                  color: hasValue
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.w600,
                    color: hasValue ? Colors.black87 : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPalletizerRow({
    required BuildContext context,
    required bool isMobile,
    required String? palletizerName,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(
          context,
          icon: Icons.badge_outlined,
          label: 'المُشَتِّح',
          isMobile: isMobile,
        ),
        SizedBox(height: isMobile ? 12 : 14),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 20,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: line.color.withValues(alpha: 0.05),
            border: Border.all(color: line.color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 10 : 12,
                height: isMobile ? 10 : 12,
                decoration: BoxDecoration(
                  color: Colors.green.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Text(
                  palletizerName ?? '—',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تسجيل خروج المُشَتِّح',
                onPressed: () => _confirmLogout(context),
                icon: Icon(
                  Icons.logout_rounded,
                  color: line.color,
                  size: isMobile ? 22 : 24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductRow({
    required BuildContext context,
    required bool isMobile,
    required String? productName,
  }) {
    final hasProduct = productName != null && productName.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(
          context,
          icon: Icons.inventory_2_outlined,
          label: 'المنتج الحالي',
          isMobile: isMobile,
        ),
        SizedBox(height: isMobile ? 12 : 14),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 20,
            vertical: isMobile ? 14 : 18,
          ),
          decoration: BoxDecoration(
            color: hasProduct
                ? line.color.withValues(alpha: 0.05)
                : Colors.grey.shade50,
            border: Border.all(
              color: hasProduct
                  ? line.color.withValues(alpha: 0.3)
                  : Colors.grey.shade200,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasProduct ? productName : '—',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w700,
                  color: hasProduct ? Colors.black87 : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isMobile ? 4 : 6),
              Text(
                'المنتج مُدار من تطبيق التشكيل الحراري',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 12 : 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'تسجيل خروج المُشَتِّح',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل تريد تسجيل خروج المُشَتِّح من هذا الخط؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: line.color,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'خروج',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<PalletizingProvider>().palletizerLogout(line.number);
    }
  }
}
