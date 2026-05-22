import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/takeover_status.dart';
import '../providers/palletizing_provider.dart';
import 'takeover_countdown.dart';

/// High-priority blocking dialog shown once when a line receives a new
/// `LINE_TAKEOVER_REQUESTED`. The Pallet Worker App is a passive observer —
/// the only action is acknowledging ("حسناً"), which collapses the dialog into
/// the persistent [TakeoverBanner]. There are no accept/reject buttons.
///
/// Show with:
/// ```dart
/// showDialog(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => TakeoverDialog(lineNumber: n),
/// );
/// ```
class TakeoverDialog extends StatefulWidget {
  final int lineNumber;

  const TakeoverDialog({super.key, required this.lineNumber});

  @override
  State<TakeoverDialog> createState() => _TakeoverDialogState();
}

class _TakeoverDialogState extends State<TakeoverDialog> {
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);

  bool _popped = false;

  void _close() {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final takeover = provider.getTakeover(widget.lineNumber);
    final status = takeover?.status ?? TakeoverStatus.unknown;

    // The takeover ended (rejected / completed / cancelled / cleared) while the
    // dialog was open → auto-close. A PENDING→ACCEPTED flip keeps it open and
    // just switches the body + countdown below.
    if (takeover == null || !status.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }

    final isAccepted = status == TakeoverStatus.accepted;

    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: _amberLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.swap_horizontal_circle_outlined,
                  color: _amberDark,
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'طلب استلام الخط',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ماكنة ${widget.lineNumber}',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _amberDark,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _amberLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isAccepted
                      ? 'المشغّل الحالي يقوم بإكمال التسليم، الرجاء الانتظار…'
                      : 'الرجاء إخبار المشغّل المناوب الحالي أن المشغّل القادم '
                            'قام بطلب استلام الخط، وأن يفتح تطبيق المشغّل ليقرّر.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    height: 1.7,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TakeoverCountdown(
                lineNumber: widget.lineNumber,
                color: _amberDark,
                handover: isAccepted,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.read<PalletizingProvider>().acknowledgeTakeover(
                    widget.lineNumber,
                  );
                  _close();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'حسناً',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
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
