import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/first_pallet_suggestion.dart';

class FirstPalletSuggestionCard extends StatelessWidget {
  final FirstPalletSuggestion suggestion;
  final Color themeColor;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  const FirstPalletSuggestionCard({
    super.key,
    required this.suggestion,
    required this.themeColor,
    this.onAccept,
    this.onDismiss,
  });

  /// Show as a modal dialog and return true if accepted, false if dismissed.
  static Future<bool?> showAsDialog({
    required BuildContext context,
    required FirstPalletSuggestion suggestion,
    required Color themeColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.isMobile(ctx) ? 16 : 40,
          vertical: 24,
        ),
        child: FirstPalletSuggestionCard(
          suggestion: suggestion,
          themeColor: themeColor,
          onAccept: () => Navigator.of(ctx).pop(true),
          onDismiss: () => Navigator.of(ctx).pop(false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = isMobile ? screenWidth * 0.9 : 440.0;

    return Container(
      width: cardWidth,
      constraints: BoxConstraints(maxWidth: cardWidth),
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(isMobile),
            SizedBox(height: isMobile ? 16 : 20),
            _buildTitle(isMobile),
            SizedBox(height: isMobile ? 12 : 16),
            _buildMessage(isMobile),
            SizedBox(height: isMobile ? 16 : 20),
            _buildQuantityInfo(isMobile),
            SizedBox(height: isMobile ? 24 : 32),
            _buildActions(isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(bool isMobile) {
    final isSameSession = suggestion.isSameSessionReturn;
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: (isSameSession ? Colors.blue : Colors.green)
            .withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isSameSession
            ? Icons.replay_rounded
            : Icons.swap_horiz_rounded,
        color: isSameSession ? Colors.blue.shade600 : Colors.green.shade600,
        size: isMobile ? 36 : 44,
      ),
    );
  }

  Widget _buildTitle(bool isMobile) {
    return Text(
      'اقتراح الطبلية الأولى',
      style: GoogleFonts.cairo(
        fontSize: isMobile ? 20 : 24,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildMessage(bool isMobile) {
    final approvedCartons = suggestion.approvedCartons ?? 0;
    final freshNeeded = suggestion.suggestedFreshQuantity ?? 0;
    final sourceOperator = suggestion.sourceOperatorName ?? '';

    final String messageText;
    if (suggestion.isSameSessionReturn) {
      messageText =
          'لديك $approvedCartons كرتونة متبقية من وقت سابق في هذه المناوبة.'
          ' تحتاج $freshNeeded كرتونة لإكمال الطبلية.';
    } else {
      messageText =
          'لديك $approvedCartons كرتونة من المناوبة السابقة ($sourceOperator).'
          ' تحتاج $freshNeeded اجمالي العبوات لإكمال الطبلية.';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        messageText,
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 14 : 16,
          color: Colors.black87,
          height: 1.6,
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      ),
    );
  }

  Widget _buildQuantityInfo(bool isMobile) {
    final approvedCartons = suggestion.approvedCartons ?? 0;
    final freshNeeded = suggestion.suggestedFreshQuantity ?? 0;
    final totalPallet = suggestion.defaultPalletQuantity ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildQuantityChip(
            label: 'فالت',
            value: '$approvedCartons',
            color: Colors.orange,
            isMobile: isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Icon(
          Icons.add_rounded,
          size: isMobile ? 20 : 24,
          color: Colors.grey.shade400,
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: _buildQuantityChip(
            label: 'جديد',
            value: '$freshNeeded',
            color: Colors.green,
            isMobile: isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Icon(
          Icons.drag_handle_rounded,
          size: isMobile ? 20 : 24,
          color: Colors.grey.shade400,
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: _buildQuantityChip(
            label: 'الطبلية',
            value: '$totalPallet',
            color: themeColor,
            isMobile: isMobile,
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityChip({
    required String label,
    required String value,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 10 : 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onDismiss,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 18),
              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'تخطي',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        SizedBox(width: isMobile ? 12 : 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              Icons.check_circle_outline_rounded,
              size: isMobile ? 20 : 22,
            ),
            label: Text(
              'تحويل لطبلية',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
