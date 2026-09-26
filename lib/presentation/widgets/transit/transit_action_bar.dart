import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/production_transit_strings.dart';
import '../../../core/theme.dart';
import '../../providers/palletizing_provider.dart';
import '../../screens/transit_scan_screen.dart';

/// Device-wide strip above the line panes (not per line) carrying the one
/// full-width «نقل إلى الرصيف» action, which opens the QR scanner (manual
/// entry is offered there). Renders nothing until a palletizer is logged in
/// on some line.
class TransitActionBar extends StatelessWidget {
  const TransitActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final canMove = context.select<PalletizingProvider, bool>(
      (p) => p.canMoveToTransit,
    );
    if (!canMove) return const SizedBox.shrink();

    return Material(
      color: AppTheme.surfaceColor,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('transitScanButton'),
            onPressed: () => TransitScanScreen.open(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                ProductionTransitStrings.action,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
