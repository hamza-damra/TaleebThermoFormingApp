import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../providers/manager_announcement_notifier.dart';

/// Global **blocking** overlay for a sanitized urgent manager announcement.
///
/// Rendered above `PalletizingScreen` (regardless of the active machine tab /
/// sub-flow) only while [ManagerAnnouncementNotifier.current] is non-null. It:
///   * blurs + dims the screen, swallows every tap, and blocks the Android back
///     button — the only exit is the "فهمت" button;
///   * renders **only** the fixed generic strings below plus the backend
///     `createdAtDisplay`. It never reads the DTO's `title` / `message`, and
///     there is no real body/sender to render — this is the defensive privacy
///     guarantee;
///   * on "فهمت" calls [ManagerAnnouncementNotifier.acknowledgeCurrent], which
///     acks every operating lineId and closes the notice only when all succeed;
///     on failure the modal stays open and shows retry text.
///
/// It does not mutate line state — when dismissed, the underlying palletizing
/// flow (auth / handover / FALET / pallet creation) is preserved exactly.
///
/// See [docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md].
class UrgentAnnouncementOverlay extends StatelessWidget {
  const UrgentAnnouncementOverlay({super.key});

  // ── Fixed generic strings (rendered verbatim — never server-provided) ──
  static const String _title = 'ملاحظة عاجلة من المدير';
  static const String _message =
      'أرسل المدير ملاحظة عاجلة للمشغل. يجب فتح تطبيق المشغل لقراءتها.';

  // ── Urgent palette (red — distinct from the amber "waiting" modals) ──
  static const Color _red = Color(0xFFDC2626);
  static const Color _redDark = Color(0xFFB91C1C);
  static const Color _redLight = Color(0xFFFEE2E2);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final notifier = context.watch<ManagerAnnouncementNotifier>();
    final announcement = notifier.current;

    // Defensive: the parent only mounts this while `current != null`, but guard
    // against a race where it clears mid-frame.
    if (announcement == null) return const SizedBox.shrink();

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
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 40),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: _buildDialog(
                        context,
                        isMobile: isMobile,
                        createdAtDisplay: announcement.createdAtDisplay,
                        acking: notifier.acking,
                        error: notifier.error,
                      ),
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

  Widget _buildDialog(
    BuildContext context, {
    required bool isMobile,
    required String createdAtDisplay,
    required bool acking,
    required String? error,
  }) {
    return Container(
      constraints: BoxConstraints(maxWidth: isMobile ? 380 : 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _red.withValues(alpha: 0.22),
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
                color: _redLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.campaign_rounded,
                color: _redDark,
                size: isMobile ? 42 : 52,
              ),
            ),
            SizedBox(height: isMobile ? 18 : 22),

            // ── Title (fixed generic string) ──
            Text(
              _title,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 22 : 27,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: isMobile ? 14 : 18),

            // ── Highlighted message box (fixed generic string) ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 18,
                vertical: isMobile ? 14 : 16,
              ),
              decoration: BoxDecoration(
                color: _redLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  height: 1.7,
                  color: Colors.grey.shade800,
                ),
              ),
            ),

            // ── Backend-formatted timestamp (only server-provided string) ──
            if (createdAtDisplay.isNotEmpty) ...[
              SizedBox(height: isMobile ? 10 : 12),
              Text(
                createdAtDisplay,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 12.5 : 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],

            // ── Ack failure retry text ──
            if (error != null) ...[
              SizedBox(height: isMobile ? 12 : 14),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 13 : 14.5,
                  fontWeight: FontWeight.w600,
                  color: _redDark,
                ),
              ),
            ],
            SizedBox(height: isMobile ? 18 : 22),

            // ── "فهمت" — the only exit path ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: acking
                    ? null
                    : () => context
                        .read<ManagerAnnouncementNotifier>()
                        .acknowledgeCurrent(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _red.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: acking
                    ? SizedBox(
                        width: isMobile ? 20 : 22,
                        height: isMobile ? 20 : 22,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'فهمت',
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
