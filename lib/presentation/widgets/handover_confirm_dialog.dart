import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';

class HandoverConfirmDialog extends StatefulWidget {
  const HandoverConfirmDialog({super.key});

  /// Show the dialog and return receiptNotes string, or null if cancelled.
  static Future<String?> show({required BuildContext context}) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const HandoverConfirmDialog(),
    );
  }

  @override
  State<HandoverConfirmDialog> createState() => _HandoverConfirmDialogState();
}

class _HandoverConfirmDialogState extends State<HandoverConfirmDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 480.0;
    final fontSize = isMobile ? 13.0 : 14.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.green.shade700,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تأكيد التسليم',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
                fontSize: isMobile ? 16 : 18,
              ),
            ),
          ),
        ],
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 20),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ملاحظات الاستلام (اختياري):',
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: 'أدخل ملاحظات الاستلام...',
                hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(12),
                isDense: true,
              ),
              style: GoogleFonts.cairo(fontSize: isMobile ? 14 : 15),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            final notes = _notesController.text.trim();
            // Return empty string to indicate "confirmed with no notes"
            Navigator.of(context).pop(notes.isEmpty ? '' : notes);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'تأكيد',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
