import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/first_pallet_suggestion.dart';
import '../../domain/entities/product_type.dart';

/// Purpose-built guided dialog for the mandatory first-pallet FALET consumption
/// case. Shown inline from the create-pallet flow when eligible approved FALET
/// must be consumed before normal pallet creation.
///
/// Returns the additional fresh quantity (>= 0) on confirm, or null on cancel.
class MandatoryFaletPalletDialog extends StatefulWidget {
  /// All display data is normalized into these fields so the dialog works
  /// both from a [FirstPalletSuggestion] and from a raw [FaletItem] fallback.
  final int faletQty;
  final int palletTarget;
  final int suggestedFresh;
  final String productName;
  final String? sourceOperatorName;
  final bool isSameSession;
  final Color themeColor;

  const MandatoryFaletPalletDialog({
    super.key,
    required this.faletQty,
    required this.palletTarget,
    required this.suggestedFresh,
    required this.productName,
    this.sourceOperatorName,
    this.isSameSession = false,
    required this.themeColor,
  });

  /// Show from a [FirstPalletSuggestion] (primary path).
  static Future<int?> show({
    required BuildContext context,
    required FirstPalletSuggestion suggestion,
    required Color themeColor,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MandatoryFaletPalletDialog(
        faletQty: suggestion.approvedCartons ?? 0,
        palletTarget: suggestion.defaultPalletQuantity ?? 0,
        suggestedFresh: suggestion.suggestedFreshQuantity ?? 0,
        productName: suggestion.productTypeName ?? '',
        sourceOperatorName: suggestion.sourceOperatorName,
        isSameSession: suggestion.isSameSessionReturn,
        themeColor: themeColor,
      ),
    );
  }

  /// Show from a raw [FaletItem] + optional product capacity (fallback path
  /// when the suggestion endpoint is unavailable).
  static Future<int?> showFromFaletItem({
    required BuildContext context,
    required FaletItem item,
    required Color themeColor,
    int? fullPalletCapacity,
  }) {
    final faletQty = item.quantity;
    final target = fullPalletCapacity ?? 0;
    final fresh = (target > faletQty) ? target - faletQty : 0;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MandatoryFaletPalletDialog(
        faletQty: faletQty,
        palletTarget: target,
        suggestedFresh: fresh,
        productName: item.productTypeName,
        sourceOperatorName: item.sourceOperatorName,
        isSameSession: item.originType == 'PRODUCT_SWITCH',
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<MandatoryFaletPalletDialog> createState() =>
      _MandatoryFaletPalletDialogState();
}

class _MandatoryFaletPalletDialogState
    extends State<MandatoryFaletPalletDialog> {
  late final TextEditingController _freshController;
  String? _validationError;

  int get _faletQty => widget.faletQty;
  int get _palletTarget => widget.palletTarget;
  int get _suggestedFresh => widget.suggestedFresh;
  int get _freshValue => int.tryParse(_freshController.text.trim()) ?? 0;
  int get _totalQuantity => _faletQty + _freshValue;

  bool get _faletAlreadyComplete =>
      _palletTarget > 0 && _faletQty >= _palletTarget;

  @override
  void initState() {
    super.initState();
    _freshController = TextEditingController(
      text: _faletAlreadyComplete ? '0' : '$_suggestedFresh',
    );
  }

  @override
  void dispose() {
    _freshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
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
                _buildFreshInput(isMobile),
              ],
              SizedBox(height: isMobile ? 14 : 18),
              _buildTotalRow(isMobile),
              if (_validationError != null) ...[
                SizedBox(height: isMobile ? 8 : 12),
                _buildValidationError(isMobile),
              ],
              SizedBox(height: isMobile ? 24 : 32),
              _buildActions(isMobile),
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
            color: widget.themeColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.playlist_add_check_rounded,
            color: widget.themeColor,
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
    final productName = ProductType.formatCompactName(widget.productName);
    final sourceOp = widget.sourceOperatorName ?? '';
    final isSameSession = widget.isSameSession;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: widget.themeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.themeColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Line 1: approved FALET quantity for this product
          Text(
            'يوجد $_faletQty عبوة فالت معتمدة لمنتج $productName',
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

          // Line 2: consumption context
          Text(
            'سيتم احتسابها الآن ضمن أول طبلية',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: widget.themeColor,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),

          // Line 3: source context (same-session vs previous shift)
          if (!isSameSession && sourceOp.isNotEmpty) ...[
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
                    Icons.person_outline_rounded,
                    size: isMobile ? 14 : 16,
                    color: Colors.grey.shade700,
                  ),
                  SizedBox(width: isMobile ? 4 : 6),
                  Text(
                    'من المناوبة السابقة ($sourceOp)',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isSameSession) ...[
            SizedBox(height: isMobile ? 6 : 8),
            Text(
              'عبوات متبقية من وقت سابق في هذه المناوبة',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 12 : 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ],
        ],
      ),
    );
  }

  // ── Quantity breakdown: FALET + target ─────────────────────────────────────

  Widget _buildQuantityBreakdown(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildQuantityCard(
            label: 'فالت معتمد',
            value: '$_faletQty',
            icon: Icons.inventory_2_outlined,
            color: widget.themeColor,
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
          ),
        ],
      ),
    );
  }

  // ── Fresh quantity input ───────────────────────────────────────────────────

  Widget _buildFreshInput(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instruction
        Text(
          'لإكمال الطبلية أضف $_suggestedFresh عبوة جديدة',
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
        SizedBox(height: isMobile ? 10 : 14),

        // Input field
        TextField(
          controller: _freshController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.bold,
            color: widget.themeColor,
          ),
          decoration: InputDecoration(
            labelText: 'الكمية الجديدة الإضافية',
            labelStyle: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              color: Colors.grey.shade600,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: widget.themeColor.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              vertical: isMobile ? 14 : 18,
              horizontal: 16,
            ),
          ),
          onChanged: (_) => setState(() => _validationError = null),
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
        color: widget.themeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.themeColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'الكمية الإجمالية للطبلية:',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            '$_totalQuantity',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
              color: widget.themeColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Validation error ──────────────────────────────────────────────────────

  Widget _buildValidationError(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        _validationError!,
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 12 : 13,
          color: Colors.red.shade700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Widget _buildActions(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null),
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
            onPressed: _handleConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.themeColor,
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

  void _handleConfirm() {
    final freshQty = _freshValue;

    if (!_faletAlreadyComplete && freshQty <= 0 && _totalQuantity <= 0) {
      setState(
        () => _validationError = 'يرجى إدخال كمية إضافية لإكمال الطبلية',
      );
      return;
    }

    Navigator.of(context).pop(freshQty);
  }
}
