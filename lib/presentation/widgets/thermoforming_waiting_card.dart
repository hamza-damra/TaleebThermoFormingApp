import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';

/// Blocking modal shown when the selected line has no active Thermoforming
/// Operator ([LineUiState.waitingForThermoforming]).
///
/// **Why an in-tree overlay, not `showDialog`:** [ProductionLineSection]
/// renders this widget as a `Positioned.fill` child *only* while the line's
/// UI state is `waitingForThermoforming`. That makes the modal a pure
/// function of backend state:
///   • It can never stack — there is no imperative `showDialog`/`pop` to
///     guard; the widget simply exists or it does not.
///   • It is naturally per-line — each machine tab builds its own
///     [ProductionLineSection], so switching tabs shows the correct line.
///   • It disappears automatically the instant a backend refresh reports an
///     operator: the parent rebuilds and stops including this child. No
///     callback, no manual dismissal.
///
/// The modal blurs + dims the underlying screen, swallows every tap, and
/// blocks the Android back button. There is intentionally **no acknowledge
/// button** — the palletizing employee cannot proceed (and cannot create
/// pallets) until the Thermoforming Operator starts/claims the line. An
/// optional "تغيير الخط" action lets the worker hop to the other machine tab
/// when that line is usable.
///
/// Uses warning/amber styling — never success green — to signal inactivity,
/// and shares the visual language of the takeover dialog.
class ThermoformingWaitingCard extends StatelessWidget {
  final ProductionLine line;

  /// When true the "تغيير الخط" secondary action is shown.
  final bool canSwitchLine;

  /// Called when the user taps "تغيير الخط". The parent is responsible for
  /// navigating the TabController / selecting another line.
  final VoidCallback? onSwitchLine;

  /// Optional title override from `LineStateResponse.waitingForOperatorMessageTitle`
  /// (V81+, 2026-05-21). When non-null, replaces the hardcoded
  /// "لا يوجد مشغّل على الخط" title. The provider already strips empty /
  /// whitespace values, so no inline trim is needed here.
  final String? titleOverride;

  /// Optional body override from `LineStateResponse.waitingForOperatorMessage`
  /// (V81+, 2026-05-21). When non-null, replaces the hardcoded body text.
  final String? bodyOverride;

  const ThermoformingWaitingCard({
    super.key,
    required this.line,
    this.canSwitchLine = false,
    this.onSwitchLine,
    this.titleOverride,
    this.bodyOverride,
  });

  // ── Warning palette (shared with TakeoverDialog) ──────────────────────────
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    // ── Full-screen blur + dim backdrop ───────────────────────────────────
    //
    // - `PopScope(canPop: false)` blocks the Android back button.
    // - The outer `GestureDetector` (opaque, empty `onTap`) absorbs taps so
    //   they never reach the production UI behind the modal.
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
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: _buildDialog(isMobile),
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

  Widget _buildDialog(bool isMobile) {
    return Container(
      constraints: BoxConstraints(maxWidth: isMobile ? 380 : 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            // ── Soft colored icon circle ──
            Container(
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              decoration: const BoxDecoration(
                color: _amberLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_off_outlined,
                color: _amberDark,
                size: isMobile ? 42 : 52,
              ),
            ),
            SizedBox(height: isMobile ? 18 : 22),

            // ── Title ──
            //
            // V81+ (2026-05-21): backend may send a localized title via
            // `LineStateResponse.waitingForOperatorMessageTitle` (e.g.
            // "بانتظار استلام الخط"). Render verbatim when provided; fall
            // back to the original hardcoded title otherwise (non-thermoforming
            // lines or pre-V81+ servers).
            Text(
              titleOverride ?? 'لا يوجد مشغّل على الخط',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 22 : 27,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),

            // ── Machine name ──
            Text(
              'ماكنة ${line.number}',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w600,
                color: _amberDark,
              ),
            ),
            SizedBox(height: isMobile ? 14 : 18),

            // ── Highlighted message box ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 18,
                vertical: isMobile ? 14 : 16,
              ),
              decoration: BoxDecoration(
                color: _amberLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                // V81+ (2026-05-21): backend body via
                // `LineStateResponse.waitingForOperatorMessage` takes
                // precedence; hardcoded fallback below is used only when the
                // backend does not provide the field.
                bodyOverride ??
                    'لا يوجد مشغّل تشكيل حراري على هذه الماكينة حاليًا. '
                        'يرجى الانتظار حتى يبدأ المشغّل مناوبته على الخط، '
                        'وسيتم فتح هذه الشاشة تلقائيًا عند توفره.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  height: 1.7,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            SizedBox(height: isMobile ? 18 : 22),

            // ── Waiting status (no acknowledge button) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: isMobile ? 16 : 18,
                  height: isMobile ? 16 : 18,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(_amberDark),
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 12),
                Text(
                  'بانتظار توفر المشغّل...',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 13.5 : 15,
                    fontWeight: FontWeight.w600,
                    color: _amberDark,
                  ),
                ),
              ],
            ),

            // ── Secondary: "تغيير الخط" (optional) ──
            if (canSwitchLine && onSwitchLine != null) ...[
              SizedBox(height: isMobile ? 18 : 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSwitchLine,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 14 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    size: isMobile ? 20 : 24,
                  ),
                  label: Text(
                    'تغيير الخط',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 15 : 17,
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
