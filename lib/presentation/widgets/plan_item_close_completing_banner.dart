import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/constants/plan_item_close_request_strings.dart';
import '../../domain/entities/palletizing_line.dart';
import '../providers/palletizing_provider.dart';
import 'line_scoped_route.dart';
import 'plan_item_close_request_dialog.dart';

/// Persistent, **non-blocking** banner for a close request in
/// `PALLETIZER_COMPLETING_PALLETS` (handoff §12): the palletizer said pallets
/// remain, keeps registering them normally, and confirms from here when done.
///
/// Re-derived from the provider's authoritative state on every build, so it
/// survives navigation, restarts and re-login, and disappears the moment the
/// request is confirmed, cancelled or invalidated. Renders nothing otherwise.
class PlanItemCloseCompletingBanner extends StatefulWidget {
  final PalletizingLine line;

  const PlanItemCloseCompletingBanner({super.key, required this.line});

  @override
  State<PlanItemCloseCompletingBanner> createState() =>
      _PlanItemCloseCompletingBannerState();
}

class _PlanItemCloseCompletingBannerState
    extends State<PlanItemCloseCompletingBanner> {
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);

  /// Guards against a double tap opening two confirmation dialogs.
  bool _confirmOpen = false;

  Future<void> _openFinalConfirm(int closeRequestId) async {
    if (_confirmOpen) return;
    _confirmOpen = true;
    final lineId = widget.line.lineId;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LineScopedRoute(
          lineId: lineId,
          child: PlanItemCloseFinalConfirmDialog(
            lineId: lineId,
            closeRequestId: closeRequestId,
          ),
        ),
      );
    } finally {
      _confirmOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final lineId = widget.line.lineId;
    final request = provider.getActiveCloseRequest(lineId);
    if (request == null || !request.isCompletingPallets) {
      return const SizedBox.shrink();
    }
    final inFlight = provider.isCloseRequestDecisionInFlight(lineId);
    final error = provider.getCloseRequestDecisionError(lineId);
    final accent = widget.line.color;
    final backendProduct = request.productTypeName;
    final product = backendProduct == null || backendProduct.trim().isEmpty
        ? null
        : provider.productDisplayName(
            productTypeId: request.productTypeId,
            backendName: backendProduct,
          );
    final progress =
        '${PlanItemCloseRequestStrings.producedLabel}: '
        '${request.producedPackageQuantity} / '
        '${request.targetPackageQuantity}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: ValueKey('close-request-banner-$lineId'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _amberLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _amber.withValues(alpha: 0.7), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: _amberDark,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PlanItemCloseRequestStrings.bannerTitle,
                        style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _amberDark,
                        ),
                      ),
                      Text(
                        PlanItemCloseRequestStrings.bannerBody,
                        style: GoogleFonts.cairo(
                          fontSize: 14.5,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      Text(
                        product != null && product.trim().isNotEmpty
                            ? '$product · $progress'
                            : progress,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: GoogleFonts.cairo(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade800,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: inFlight
                  ? null
                  : () => _openFinalConfirm(request.closeRequestId),
              icon: inFlight
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Icon(Icons.task_alt_rounded),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  PlanItemCloseRequestStrings.bannerAction,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
