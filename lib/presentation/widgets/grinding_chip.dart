import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small amber chip carrying backend-supplied grinding text — the label
/// marker «(موصى بالجرش)» or a grinding order's Arabic status label. The text
/// is shown verbatim; this widget never composes grinding wording itself.
class GrindingChip extends StatelessWidget {
  final String text;
  final double fontSize;

  const GrindingChip({super.key, required this.text, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.recycling_rounded,
            size: fontSize + 3,
            color: Colors.orange.shade800,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
