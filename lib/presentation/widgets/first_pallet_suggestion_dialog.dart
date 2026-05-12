import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/first_pallet_context.dart';

/// Result of the first-pallet suggestion dialog.
enum FirstPalletDialogResult {
  /// User opted to consume the matching FALET — the suggested quantity should
  /// be pre-filled in the normal CreatePalletDialog and the product type
  /// pre-selected from the context.
  useFalet,

  /// User declined the suggestion — proceed to a normal pallet creation.
  skipFalet,
}

class FirstPalletSuggestionDialog extends StatelessWidget {
  final ProductionLine line;
  final FirstPalletContext context;

  const FirstPalletSuggestionDialog({
    super.key,
    required this.line,
    required this.context,
  });

  @override
  Widget build(BuildContext buildContext) {
    final isMobile = ResponsiveHelper.isMobile(buildContext);
    final screenWidth = MediaQuery.of(buildContext).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 440.0;
    final spacing = isMobile ? 12.0 : 16.0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.inventory_2_rounded,
            color: line.color,
            size: isMobile ? 22 : 26,
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Text(
              'إنشاء أول طبلية',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: line.color,
                fontSize: isMobile ? 16 : 20,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 24),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((context.messageAr ?? '').isNotEmpty)
              _MessageBanner(text: context.messageAr!, color: line.color),
            SizedBox(height: spacing),
            _buildInfoCard(isMobile),
          ],
        ),
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 20,
        0,
        isMobile ? 12 : 20,
        isMobile ? 12 : 16,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(buildContext).pop(
            FirstPalletDialogResult.skipFalet,
          ),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 20,
              vertical: isMobile ? 10 : 12,
            ),
            side: BorderSide(color: Colors.grey.shade400, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'متابعة بدون فالت',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(buildContext).pop(
            FirstPalletDialogResult.useFalet,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: line.color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 10 : 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'استخدام الفالت ومتابعة',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(bool isMobile) {
    final rows = <Widget>[];
    final product = context.currentProductName;
    if (product != null && product.isNotEmpty) {
      rows.add(_InfoRow(label: 'المنتج الحالي', value: product));
    }
    final pkg = context.packageQuantity;
    if (pkg != null && pkg > 0) {
      rows.add(_InfoRow(label: 'حجم الطبلية', value: '$pkg'));
    }
    rows.add(_InfoRow(
      label: 'الفالت المطابق المتاح',
      value: '${context.matchingProductFaletQuantity}',
    ));
    final suggested = context.suggestedFaletQuantityForFirstPallet;
    if (suggested != null) {
      rows.add(_InfoRow(
        label: 'الكمية المقترحة من الفالت',
        value: '$suggested',
        highlight: true,
        highlightColor: line.color,
      ));
    }

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String text;
  final Color color;

  const _MessageBanner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? highlightColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            textDirection: TextDirection.rtl,
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: highlight ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: highlight ? highlightColor : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
