import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/production_transit_strings.dart';
import '../../../core/theme.dart';
import '../../../domain/entities/production_transit.dart';
import '../../providers/palletizing_provider.dart';

/// The backend's display string, else [at] in device-local time in the same
/// «2026-09-24، 02:40 مساءً» shape (refusal details carry no display field).
String transitTimeText(DateTime? at, String? display) {
  if (display != null && display.trim().isNotEmpty) return display;
  if (at == null) return '—';
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final period = t.hour >= 12 ? 'مساءً' : 'صباحاً';
  return '${t.year}-${two(t.month)}-${two(t.day)}، '
      '${two(hour12)}:${two(t.minute)} $period';
}

/// A compact status pill in the same visual language as [GrindingChip]
/// («تم الجرش»): tinted fill, tinted border, icon and bold text.
class TransitStatusPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final double fontSize;

  const TransitStatusPill({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 3, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «موروثة من وردية سابقة» — a pallet carried over from an earlier shift.
class InheritedPalletChip extends StatelessWidget {
  final double fontSize;

  const InheritedPalletChip({super.key, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    return TransitStatusPill(
      text: ProductionTransitStrings.inheritedChip,
      icon: Icons.history_rounded,
      color: AppTheme.primaryDark,
      fontSize: fontSize,
    );
  }
}

/// «تم النقل إلى الرصيف» — the pallet's authoritative location is TRANSIT.
class TransitLocationChip extends StatelessWidget {
  final double fontSize;

  const TransitLocationChip({super.key, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return TransitStatusPill(
      text: ProductionTransitStrings.movedToTransitBadge,
      icon: Icons.local_shipping_rounded,
      color: AppTheme.successColor,
      fontSize: fontSize,
    );
  }
}

/// The 12-digit pallet number: always left-to-right, always on one line —
/// scaled down rather than wrapped in a narrow card.
class PalletNumberText extends StatelessWidget {
  final String value;
  final double fontSize;

  const PalletNumberText(this.value, {super.key, this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        textDirection: TextDirection.ltr,
        style: GoogleFonts.robotoMono(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// One pallet still at PRODUCTION: number, product, produced time,
/// palletizer and the inherited chip, with an optional compact [trailing]
/// action or status.
class PendingPalletTile extends StatelessWidget {
  final ProductionPendingPallet pallet;
  final Widget? trailing;

  /// Tints the card once the pallet no longer blocks.
  final bool resolved;

  const PendingPalletTile({
    super.key,
    required this.pallet,
    this.trailing,
    this.resolved = false,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PalletizingProvider>();
    final product = provider.productDisplayName(
      productTypeId: pallet.productTypeId,
      backendName: pallet.productTypeName,
    );
    final meta = GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700);
    final palletizer = pallet.palletizerName?.trim() ?? '';

    return Container(
      key: ValueKey('pending-pallet-${pallet.scannedValue}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: resolved
            ? AppTheme.successColor.withValues(alpha: 0.05)
            : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: resolved
              ? AppTheme.successColor.withValues(alpha: 0.35)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PalletNumberText(pallet.scannedValue),
                if (product.isNotEmpty)
                  Text(
                    product,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                _metaLine(
                  Icons.schedule_rounded,
                  transitTimeText(pallet.producedAt, pallet.producedAtDisplay),
                  meta,
                ),
                if (palletizer.isNotEmpty)
                  _metaLine(Icons.badge_outlined, palletizer, meta),
                if (pallet.inherited) ...[
                  const SizedBox(height: 4),
                  const InheritedPalletChip(),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 124),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaLine(IconData icon, String text, TextStyle style) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// The outcome of one move attempt — green only for a real move.
class TransitMoveResultCard extends StatelessWidget {
  final TransitMoveOutcome outcome;

  const TransitMoveResultCard({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PalletizingProvider>();
    final (IconData icon, Color color) = switch (outcome.status) {
      TransitMoveStatus.moved => (
        Icons.check_circle_rounded,
        AppTheme.successColor,
      ),
      TransitMoveStatus.returnedToProduction => (
        Icons.undo_rounded,
        AppTheme.warningColor,
      ),
      TransitMoveStatus.notAtProduction => (
        Icons.info_rounded,
        AppTheme.primaryColor,
      ),
      TransitMoveStatus.voided => (
        Icons.delete_sweep_rounded,
        AppTheme.warningColor,
      ),
      TransitMoveStatus.retryable => (
        Icons.wifi_off_rounded,
        AppTheme.errorColor,
      ),
      TransitMoveStatus.sessionLost => (
        Icons.lock_clock_rounded,
        AppTheme.errorColor,
      ),
      TransitMoveStatus.refused => (Icons.block_rounded, AppTheme.errorColor),
      TransitMoveStatus.ignored => (Icons.hourglass_empty_rounded, Colors.grey),
    };
    final result = outcome.result;
    final rows = <(String, String)>[
      if (result != null) ...[
        if ((result.productTypeName ?? '').isNotEmpty ||
            result.productTypeId != null)
          (
            ProductionTransitStrings.productLabel,
            provider.productDisplayName(
              productTypeId: result.productTypeId,
              backendName: result.productTypeName,
            ),
          ),
        if ((result.palletizingLineName ?? '').isNotEmpty)
          (ProductionTransitStrings.lineLabel, result.palletizingLineName!),
        if (outcome.status == TransitMoveStatus.moved) ...[
          (
            ProductionTransitStrings.movedAtLabel,
            transitTimeText(result.movedAt, result.movedAtDisplay),
          ),
          if ((result.movedByName ?? '').isNotEmpty)
            (ProductionTransitStrings.movedByLabel, result.movedByName!),
        ],
      ],
      if (outcome.status == TransitMoveStatus.notAtProduction ||
          (outcome.status == TransitMoveStatus.voided &&
              !outcome.needsNewScan &&
              outcome.currentLocation != null))
        (
          ProductionTransitStrings.currentLocationLabel,
          ProductionTransitStrings.locationLabel(outcome.currentLocation),
        ),
    ];

    return Container(
      key: ValueKey('transit-outcome-${outcome.status.name}'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 8),
          Text(
            outcome.message,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (outcome.needsNewScan) ...[
            const SizedBox(height: 4),
            Text(
              ProductionTransitStrings.requestVoidedScanAgain,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
            ),
          ],
          if (outcome.scannedValue.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(child: PalletNumberText(outcome.scannedValue, fontSize: 18)),
          ],
          if (result?.inherited ?? false) ...[
            const SizedBox(height: 6),
            const InheritedPalletChip(),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Text(
                      '$label: ',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
