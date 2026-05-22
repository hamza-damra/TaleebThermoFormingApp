import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// State C top context strip for a single line. Three read-only identity rows
/// in the existing card style: operator on duty (المشغّل), palletizer using
/// this device (موظف الطبليات — with a small logout icon), and current product
/// (المنتج الحالي — read-only, sourced from the Thermoforming Production
/// Plan item).
class LineContextStrip extends StatelessWidget {
  final ProductionLine line;

  const LineContextStrip({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final operator = provider.getAuthorizedOperator(line.number);
    final palletizerName = provider.getPalletizerName(line.number);

    // Source of truth is the current Thermoforming Production Plan item. When
    // there is no plan item the row renders an explicit no-plan state.
    final planProductName =
        provider.getCurrentPlanItemProductName(line.number);
    final planBlockedMessage =
        provider.getProductionPlanBlockedMessage(line.number);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIdentityRow(
          context: context,
          isMobile: isMobile,
          icon: Icons.person_outline_rounded,
          label: 'المشغّل',
          // When no operator is bound the line is in a waiting state and the
          // ThermoformingWaitingCard overlay covers this strip. The fallback
          // text is intentionally neutral (no warning pill) so any race-window
          // glimpse never reads as an "active production" cue.
          value: operator?.displayLabel ?? 'غير متوفر',
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
          productName: planProductName,
          planBlockedMessage: planBlockedMessage,
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
                  : Colors.grey.shade300,
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
                    color: hasValue ? Colors.black87 : Colors.grey.shade500,
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
          label: 'موظف الطبليات',
          isMobile: isMobile,
        ),
        SizedBox(height: isMobile ? 12 : 14),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 20,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: palletizerName != null
                ? line.color.withValues(alpha: 0.05)
                : Colors.grey.shade50,
            border: Border.all(
              color: palletizerName != null
                  ? line.color.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 10 : 12,
                height: isMobile ? 10 : 12,
                decoration: BoxDecoration(
                  color: palletizerName != null
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Text(
                  palletizerName ?? 'غير متوفر',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 15 : 17,
                    fontWeight: FontWeight.w600,
                    color: palletizerName != null
                        ? Colors.black87
                        : Colors.grey.shade500,
                  ),
                ),
              ),
              if (palletizerName != null) _LeaveLineButton(line: line),
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
    required String? planBlockedMessage,
  }) {
    final hasProduct = productName != null && productName.isNotEmpty;
    // No active plan item — show the backend-localized message (or a safe
    // Arabic fallback) instead of a product label.
    final emptyText = planBlockedMessage ??
        'لا يوجد بند إنتاج نشط لهذا الخط. '
            'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelRow(
          context,
          icon: Icons.inventory_2_outlined,
          label: 'المنتج المخطط',
          isMobile: isMobile,
        ),
        SizedBox(height: isMobile ? 12 : 14),
        Container(
          width: double.infinity,
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
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 10 : 12,
                height: isMobile ? 10 : 12,
                decoration: BoxDecoration(
                  color: hasProduct
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasProduct ? productName : emptyText,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 15 : 17,
                        fontWeight: FontWeight.w600,
                        color: hasProduct
                            ? Colors.black87
                            : Colors.grey.shade700,
                        height: 1.4,
                      ),
                      softWrap: true,
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'المنتج مُدار من خطة الإنتاج (تطبيق التشكيل الحراري)',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 12 : 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

/// Red, clearly-destructive "leave the line now" action shown in the
/// "موظف الطبليات" row — replaces the old logout icon button.
///
/// Tapping it asks for an explicit responsibility-accepting confirmation,
/// then calls the existing [PalletizingProvider.palletizerLogout] release
/// path **exactly once**. It is a [StatefulWidget] purely so it can guard
/// against double taps: once the release is in flight `_isLeaving` disables
/// the button and shows a spinner until it completes.
class _LeaveLineButton extends StatefulWidget {
  final ProductionLine line;

  const _LeaveLineButton({required this.line});

  @override
  State<_LeaveLineButton> createState() => _LeaveLineButtonState();
}

class _LeaveLineButtonState extends State<_LeaveLineButton> {
  /// True while [PalletizingProvider.palletizerLogout] is in flight — blocks
  /// re-entry so a second tap can never fire a duplicate release.
  bool _isLeaving = false;

  Future<void> _handleTap() async {
    if (_isLeaving) return;

    final confirmed = await _confirmLeave();
    // The strip may be torn down while the dialog is open (e.g. the line state
    // changed underneath us) — bail before touching state / context again.
    if (confirmed != true || !mounted) return;

    setState(() => _isLeaving = true);
    // Capture the messenger before the await so we never read context after
    // this widget may have been disposed by the post-logout state change.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PalletizingProvider>().palletizerLogout(
        widget.line.number,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'تعذّر إتمام مغادرة الخط. الرجاء المحاولة مرة أخرى.',
            style: GoogleFonts.cairo(),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } finally {
      // A successful logout drops the line to State B and disposes this
      // widget — only touch state when still mounted.
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  Future<bool?> _confirmLeave() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'تأكيد مغادرة الخط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'أنت على وشك مغادرة الخط قبل انتهاء المناوبة الحالية. '
            'قد يؤدي ذلك إلى تعطيل متابعة الإنتاج على هذه الماكينة، '
            'وستتحمل مسؤولية هذا الإجراء. هل تريد المتابعة؟',
            style: GoogleFonts.cairo(height: 1.7),
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
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'نعم، مغادرة الآن',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    return TextButton.icon(
      onPressed: _isLeaving ? null : _handleTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.red.shade600,
        disabledForegroundColor: Colors.red.shade200,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12,
          vertical: isMobile ? 6 : 8,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: _isLeaving
          ? SizedBox(
              width: isMobile ? 15 : 16,
              height: isMobile ? 15 : 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade400),
              ),
            )
          : Icon(Icons.logout_rounded, size: isMobile ? 18 : 20),
      label: Text(
        'مغادرة الآن',
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 13.5 : 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
