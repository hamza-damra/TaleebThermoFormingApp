import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../domain/entities/takeover_status.dart';
import '../providers/palletizing_provider.dart';
import 'takeover_countdown.dart';

/// Persistent, **non-blocking** banner shown at the top of a production line
/// after the worker acknowledges the takeover dialog. It informs without
/// freezing the line — PENDING/ACCEPTED lines stay usable for production
/// unless the backend says otherwise (see [PalletizingProvider.isPalletCreationBlocked]).
///
/// Renders nothing when there is no takeover or it has cleared.
class TakeoverBanner extends StatelessWidget {
  final ProductionLine line;

  const TakeoverBanner({super.key, required this.line});

  // ── Warning palette (consistent with ThermoformingWaitingCard) ──
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);
  // Auto-released is a hard block — a deeper orange-red signals "stop".
  static const Color _release = Color(0xFFC2410C);
  static const Color _releaseLight = Color(0xFFFFEDD5);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final takeover = provider.getTakeover(line.number);

    if (takeover == null) return const SizedBox.shrink();
    final status = takeover.status;
    if (status.isCleared || status == TakeoverStatus.unknown) {
      return const SizedBox.shrink();
    }

    final bool autoReleased = status.isAutoReleased;
    final bool accepted = status == TakeoverStatus.accepted;

    final Color accent = autoReleased ? _release : _amberDark;
    final Color bg = autoReleased ? _releaseLight : _amberLight;
    final Color border = autoReleased ? _release : _amber;

    final String message;
    if (autoReleased) {
      message = 'انتهت المهلة — بانتظار استلام المشغّل القادم للخط.';
    } else if (accepted) {
      message = 'المشغّل الحالي يقوم بإكمال التسليم، الرجاء الانتظار…';
    } else {
      message =
          'الرجاء إخبار المشغّل المناوب الحالي أن المشغّل القادم '
          'قام بطلب استلام الخط.';
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                autoReleased
                    ? Icons.error_outline_rounded
                    : Icons.swap_horizontal_circle_outlined,
                color: accent,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طلب استلام الخط',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: GoogleFonts.cairo(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    if (!autoReleased) ...[
                      const SizedBox(height: 8),
                      TakeoverCountdown(
                        lineNumber: line.number,
                        color: accent,
                        handover: accepted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
