import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// Overlay for [LineUiState.blocked] — a line with an active operator that the
/// backend has flagged as currently unusable for a reason that is NOT a
/// pending legacy handover, NOT a missing operator, and NOT a takeover
/// (those have their own dedicated overlays).
///
/// Previously the `blocked` UI state rendered no overlay at all, so a real
/// backend block surfaced only as a disabled "Create Pallet" button — the
/// worker saw nothing explaining why. Worse, downstream API rejections during
/// that window could bubble into snackbars carrying a generic credentials
/// error. This card replaces that empty hole with an explicit, neutral
/// "الخط محظور حالياً" surface that maps known `blockedReason` values to
/// localized Arabic copy and exposes a manual refresh.
class LineBlockedCard extends StatefulWidget {
  final ProductionLine line;

  const LineBlockedCard({super.key, required this.line});

  @override
  State<LineBlockedCard> createState() => _LineBlockedCardState();
}

class _LineBlockedCardState extends State<LineBlockedCard> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await context.read<PalletizingProvider>().refreshLineState(
      widget.line.number,
    );
    if (mounted) setState(() => _isRefreshing = false);
  }

  /// Map backend `blockedReason` strings to localized Arabic. Unknown codes
  /// fall back to a generic, non-alarming message — never a credentials error.
  String _localizedReason(String? reason) {
    switch (reason) {
      case 'PENDING_HANDOVER':
      case 'LINE_BLOCKED_BY_PENDING_HANDOVER':
        return 'الخط بانتظار استلام المناوبة';
      case 'LINE_NOT_AUTHORIZED':
        return 'الخط لم يتم تفعيله بواسطة مشغّل التشكيل بعد';
      case 'EQUIPMENT_FAULT':
        return 'هناك عطل معدّاتي على هذا الخط';
      case 'PRODUCTION_PLAN_ITEM_REQUIRED':
        return 'لا يوجد بند إنتاج نشط لهذا الخط';
      case 'NO_ACTIVE_THERMOFORMING_OPERATOR':
        return 'لا يوجد مشغّل تشكيل حراري نشط على الخط';
      default:
        // Unknown reasons render as a neutral block message — the screen
        // never invents credential text from an unrecognized code.
        return 'هذا الخط محظور مؤقتاً من قبل النظام';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final provider = context.watch<PalletizingProvider>();
    final reason = provider.getBlockedReason(widget.line.number);
    final body = _localizedReason(reason);

    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 24 : 40,
                    ),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: _buildDialog(isMobile, body, reason),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialog(bool isMobile, String body, String? reason) {
    return Container(
      constraints: BoxConstraints(maxWidth: isMobile ? 380 : 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 24 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pause_circle_outline_rounded,
                color: Colors.orange.shade800,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 20),
            Text(
              'الخط محظور حالياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 22 : 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ماكنة ${widget.line.number}',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800,
              ),
            ),
            SizedBox(height: isMobile ? 14 : 18),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  height: 1.7,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            SizedBox(height: isMobile ? 20 : 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isRefreshing ? null : _handleRefresh,
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.line.color,
                  side: BorderSide(color: widget.line.color, width: 1.5),
                  padding: EdgeInsets.symmetric(
                    vertical: isMobile ? 14 : 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isRefreshing
                    ? SizedBox(
                        width: isMobile ? 18 : 20,
                        height: isMobile ? 18 : 20,
                        child: CircularProgressIndicator(
                          color: widget.line.color,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: isMobile ? 20 : 24,
                      ),
                label: Text(
                  'تحديث',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 18,
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
}
