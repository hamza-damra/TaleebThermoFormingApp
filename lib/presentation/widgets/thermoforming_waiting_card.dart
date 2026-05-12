import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// Full-screen blocking modal overlay shown when the selected line has no
/// active Thermoforming Operator ([LineUiState.waitingForThermoforming]).
///
/// The overlay **blurs and dims** the entire underlying content so the worker
/// clearly sees that the line is unusable. It is NOT dismissible by tapping
/// outside or by the back button — the only exit paths are:
///   • The "تحديث الحالة" button (re-fetches backend state).
///   • The optional "تغيير الخط" button (switches to another active line tab).
///   • Automatic dismissal when the provider detects a new operator.
///
/// Uses warning/amber styling — never success green — to signal inactivity.
class ThermoformingWaitingCard extends StatefulWidget {
  final ProductionLine line;

  /// When true the "تغيير الخط" secondary action is shown.
  final bool canSwitchLine;

  /// Called when the user taps "تغيير الخط". The parent is responsible for
  /// navigating the TabController / selecting another line.
  final VoidCallback? onSwitchLine;

  const ThermoformingWaitingCard({
    super.key,
    required this.line,
    this.canSwitchLine = false,
    this.onSwitchLine,
  });

  @override
  State<ThermoformingWaitingCard> createState() =>
      _ThermoformingWaitingCardState();
}

class _ThermoformingWaitingCardState extends State<ThermoformingWaitingCard> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await context.read<PalletizingProvider>().refreshLineState(
      widget.line.number,
    );
    if (mounted) setState(() => _isRefreshing = false);
  }

  // ── Warning palette ────────────────────────────────────────────────────────
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);
  static const Color _amberIconBg = Color(0x1AF59E0B); // 10%
  static const Color _amberBorder = Color(0x4DF59E0B); // 30%

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    // ── Full-screen blur + dim backdrop ───────────────────────────────────
    //
    // - `PopScope(canPop: false)` blocks the Android back button from
    //   dismissing the waiting state.
    // - The outer `GestureDetector` with `HitTestBehavior.opaque` and an
    //   empty `onTap` absorbs taps so they never reach the underlying
    //   production UI (which must be uninteractive while in waiting mode).
    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 24 : 40,
                    ),
                    child: _buildDialog(isMobile),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialog(bool isMobile) {
    return Container(
      constraints: BoxConstraints(maxWidth: isMobile ? 380 : 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _amberBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 28 : 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ──
            Container(
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              decoration: const BoxDecoration(
                color: _amberIconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hourglass_top_rounded,
                color: _amberDark,
                size: isMobile ? 42 : 52,
              ),
            ),
            SizedBox(height: isMobile ? 20 : 24),

            // ── Title ──
            Text(
              'بانتظار استلام الخط',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 12 : 14),

            // ── Body ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 18,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: BoxDecoration(
                color: _amberLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'تم إنهاء مناوبة مشغّل التشكيل أو لا يوجد مشغّل حالي على هذا الخط.\n'
                'لا يمكن تكوين طلبية جديدة حتى يستلم مشغّل التشكيل الخط من تطبيقه.',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  color: Colors.grey.shade800,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: isMobile ? 28 : 36),

            // ── Primary: "تحديث الحالة" ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRefreshing ? null : _handleRefresh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _amber.withValues(alpha: 0.5),
                  padding: EdgeInsets.symmetric(
                    vertical: isMobile ? 16 : 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: _isRefreshing
                    ? SizedBox(
                        width: isMobile ? 20 : 22,
                        height: isMobile ? 20 : 22,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: isMobile ? 22 : 26,
                      ),
                label: Text(
                  'تحديث الحالة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // ── Secondary: "تغيير الخط" (optional) ──
            if (widget.canSwitchLine && widget.onSwitchLine != null) ...[
              SizedBox(height: isMobile ? 12 : 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onSwitchLine,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(
                      color: Colors.grey.shade400,
                      width: 1.5,
                    ),
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 14 : 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    size: isMobile ? 22 : 26,
                  ),
                  label: Text(
                    'تغيير الخط',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
