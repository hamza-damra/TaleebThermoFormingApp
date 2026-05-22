import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warning dialog shown when the backend rejects a pallet creation with
/// `PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED` (V81 plan
/// enforcement). The same create-pallet request is then re-sent with
/// `confirmOverproduction: true` only if the operator confirms here.
///
/// Returns `true` to proceed, `false` (or `null`, treated as `false`) to abort.
class OverproductionConfirmationDialog extends StatelessWidget {
  /// Optional backend-localized body text (e.g. ApiException.displayMessage).
  /// Used verbatim when present; otherwise we fall back to the standard
  /// Arabic body the spec requires.
  final String? message;

  const OverproductionConfirmationDialog({super.key, this.message});

  /// Convenience: shows the dialog and returns whether the operator confirmed.
  static Future<bool> show(BuildContext context, {String? message}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OverproductionConfirmationDialog(message: message),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD97706), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تم تجاوز حد الخطة',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD97706),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          (message != null && message!.trim().isNotEmpty)
              ? message!
              : 'العدد الحالي تجاوز الكمية المطلوبة. هل تريد المتابعة؟',
          style: GoogleFonts.cairo(height: 1.7, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'متابعة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
