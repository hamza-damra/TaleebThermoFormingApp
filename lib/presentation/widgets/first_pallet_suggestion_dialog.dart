import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/first_pallet_context.dart';

/// First-pallet FALET-consumption confirmation.
///
/// Visual design ported from the original `MandatoryFaletPalletDialog`
/// (commit c8ff1c3, deleted in eb1f28d) — restored after the May-12 refactor
/// (3a36ab2) replaced it with a cramped AlertDialog. UI is faithful to the
/// pre-refactor screenshots; business logic stays on the current model.
///
/// FALET bypass is FORBIDDEN. The only outcomes are:
///   * `true`  → operator confirmed; consume matching FALET as the first pallet
///   * `null`  → operator cancelled / dismissed
class FirstPalletSuggestionDialog extends StatelessWidget {
  final ProductionLine line;
  final FirstPalletContext context;

  const FirstPalletSuggestionDialog({
    super.key,
    required this.line,
    required this.context,
  });

  // Effective values pulled from the backend-provided context. The suggested
  // FALET count is what the server says to consume; `palletTarget` is the
  // current plan item's pallet size. `freshNeeded` is the additional new
  // packages required to fill the pallet (>=0).
  int get _faletQty =>
      context.suggestedFaletQuantityForFirstPallet ??
      context.matchingProductFaletQuantity;
  int get _palletTarget => context.currentPlanItemPackagesPerPallet ?? 0;
  int get _freshNeeded =>
      (_palletTarget > _faletQty) ? _palletTarget - _faletQty : 0;
  String get _productName => context.currentPlanItemProductName ?? '';
  bool get _faletAlreadyComplete =>
      _palletTarget > 0 && _faletQty >= _palletTarget;
  int get _totalQuantity =>
      _faletAlreadyComplete ? _faletQty : (_faletQty + _freshNeeded);

  @override
  Widget build(BuildContext buildContext) {
    final isMobile = ResponsiveHelper.isMobile(buildContext);
    final screenWidth = MediaQuery.of(buildContext).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.92 : 460.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 40,
        vertical: 24,
      ),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxWidth: dialogWidth),
        padding: EdgeInsets.all(isMobile ? 20 : 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isMobile),
              SizedBox(height: isMobile ? 16 : 20),
              _buildFaletInfoBanner(isMobile),
              SizedBox(height: isMobile ? 14 : 18),
              _buildQuantityBreakdown(isMobile),
              if (!_faletAlreadyComplete) ...[
                SizedBox(height: isMobile ? 14 : 18),
                _buildFreshDisplay(isMobile),
              ],
              SizedBox(height: isMobile ? 14 : 18),
              _buildTotalRow(isMobile),
              SizedBox(height: isMobile ? 24 : 32),
              _buildActions(buildContext, isMobile),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header: icon + title ──────────────────────────────────────────────────

  Widget _buildHeader(bool isMobile) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: line.color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.playlist_add_check_rounded,
            color: line.color,
            size: isMobile ? 36 : 44,
          ),
        ),
        SizedBox(height: isMobile ? 12 : 16),
        Text(
          'إنشاء أول طبلية',
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // ── FALET info banner: explains the mandatory consumption ─────────────────

  Widget _buildFaletInfoBanner(bool isMobile) {
    final hasProduct = _productName.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            hasProduct
                ? 'يوجد $_faletQty عبوة فالت معتمدة لمنتج $_productName'
                : 'يوجد $_faletQty عبوة فالت معتمدة',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 15 : 17,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            'سيتم احتسابها الآن ضمن أول طبلية',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: line.color,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 14,
              vertical: isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: isMobile ? 14 : 16,
                  color: Colors.grey.shade700,
                ),
                SizedBox(width: isMobile ? 4 : 6),
                Text(
                  'من المناوبة السابقة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 12 : 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quantity breakdown: FALET + target ────────────────────────────────────

  Widget _buildQuantityBreakdown(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildQuantityCard(
            label: 'فالت معتمد',
            value: '$_faletQty',
            icon: Icons.inventory_2_outlined,
            color: line.color,
            isMobile: isMobile,
          ),
        ),
        if (_palletTarget > 0) ...[
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: _buildQuantityCard(
              label: 'هدف الطبلية',
              value: '$_palletTarget',
              icon: Icons.grid_view_rounded,
              color: Colors.grey.shade600,
              isMobile: isMobile,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantityCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 12 : 16,
        horizontal: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: isMobile ? 20 : 24),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 11 : 12,
              color: Colors.grey.shade600,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // ── Fresh quantity (read-only display) ────────────────────────────────────
  //
  // The original implementation had an editable TextField here. The current
  // workflow hands control off to CreatePalletDialog after this confirmation,
  // and that dialog is the canonical place to adjust quantity — so we show
  // the suggested additional fresh count as a read-only highlight instead of
  // duplicating quantity-editing UI. Layout/spacing matches the original.
  Widget _buildFreshDisplay(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'لإكمال الطبلية أضف $_freshNeeded عبوة جديدة',
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
        SizedBox(height: isMobile ? 10 : 14),
        Container(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 14 : 18,
            horizontal: 16,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: line.color.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                'الكمية الجديدة الإضافية',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 13 : 15,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                textDirection: TextDirection.rtl,
              ),
              SizedBox(height: isMobile ? 4 : 6),
              Text(
                '$_freshNeeded',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 22 : 26,
                  fontWeight: FontWeight.bold,
                  color: line.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Total row ─────────────────────────────────────────────────────────────

  Widget _buildTotalRow(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'الكمية الإجمالية للطبلية:',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
            textDirection: TextDirection.rtl,
          ),
          Text(
            '$_totalQuantity',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
              color: line.color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext buildContext, bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(buildContext).pop(null),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 18),
              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        SizedBox(width: isMobile ? 12 : 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(buildContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: line.color,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              Icons.check_circle_outline_rounded,
              size: isMobile ? 20 : 22,
            ),
            label: Text(
              'تأكيد وإنشاء الطبلية',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
