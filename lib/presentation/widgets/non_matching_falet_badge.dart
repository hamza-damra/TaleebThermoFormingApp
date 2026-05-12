import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Read-only badge surfaced when the line has open FALET of a *different*
/// product than the current line product. The Palletizing App never acts on
/// this FALET — the copy explicitly directs the user to the Thermoforming
/// Operator App.
class NonMatchingFaletBadge extends StatelessWidget {
  final int count;

  const NonMatchingFaletBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.amber.shade800,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'يوجد فالت من منتج آخر — يتعامل معه تطبيق مشغل الثيرموفورمنغ',
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
