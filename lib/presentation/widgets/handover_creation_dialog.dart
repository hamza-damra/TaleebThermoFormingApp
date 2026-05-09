import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';

/// Result returned from the handover creation dialog.
class HandoverCreationResult {
  final int? lastActiveProductTypeId;
  final int? lastActiveProductFaletQuantity;
  final String? notes;

  const HandoverCreationResult({
    this.lastActiveProductTypeId,
    this.lastActiveProductFaletQuantity,
    this.notes,
  });
}

class HandoverCreationDialog extends StatefulWidget {
  final List<ProductType> productTypes;
  final Color themeColor;
  final ProductType? currentProduct;

  const HandoverCreationDialog({
    super.key,
    required this.productTypes,
    required this.themeColor,
    this.currentProduct,
  });

  /// Show the dialog and return the result, or null if cancelled.
  static Future<HandoverCreationResult?> show({
    required BuildContext context,
    required List<ProductType> productTypes,
    required Color themeColor,
    ProductType? currentProduct,
  }) {
    return showDialog<HandoverCreationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HandoverCreationDialog(
        productTypes: productTypes,
        themeColor: themeColor,
        currentProduct: currentProduct,
      ),
    );
  }

  @override
  State<HandoverCreationDialog> createState() => _HandoverCreationDialogState();
}

class _HandoverCreationDialogState extends State<HandoverCreationDialog> {
  bool? _hasFalet;
  final _faletQuantityController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _faletQuantityController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _faletQuantityController.removeListener(_onFieldChanged);
    _faletQuantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 480.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, color: widget.themeColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تسليم مناوبة',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: widget.themeColor,
                fontSize: isMobile ? 16 : 18,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 20,
        isMobile ? 16 : 20,
        isMobile ? 16 : 20,
        isMobile ? 8 : 10,
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(child: _buildForm(isMobile)),
      ),
      actions: _buildActions(isMobile),
    );
  }

  Widget _buildForm(bool isMobile) {
    final fontSize = isMobile ? 13.0 : 14.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current product info
        if (widget.currentProduct != null) ...[
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: widget.themeColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.themeColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: widget.themeColor,
                  size: isMobile ? 18 : 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المنتج النشط: ${ProductType.formatCompactName(widget.currentProduct!.name)}',
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: widget.themeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // FALET explicit yes/no — only shown when there is an active product
        if (widget.currentProduct != null) ...[
          // Question label
          Text(
            'هل يوجد فالت للمنتج الحالي؟',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 15,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Yes / No selection buttons
          Row(
            children: [
              Expanded(
                child: _buildChoiceButton(
                  label: 'نعم',
                  icon: Icons.check_circle_outline,
                  selected: _hasFalet == true,
                  onTap: () => setState(() {
                    _hasFalet = true;
                  }),
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildChoiceButton(
                  label: 'لا',
                  icon: Icons.cancel_outlined,
                  selected: _hasFalet == false,
                  onTap: () => setState(() {
                    _hasFalet = false;
                    _faletQuantityController.clear();
                  }),
                  isMobile: isMobile,
                ),
              ),
            ],
          ),

          // FALET quantity input — only when yes
          if (_hasFalet == true) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'عدد عبوات الفالت:',
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _faletQuantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'عدد عبوات الفالت',
                      labelStyle: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: 'أدخل العدد',
                      hintStyle: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 14,
                        color: Colors.grey.shade400,
                      ),
                      errorText: _faletQuantityError,
                      errorStyle: GoogleFonts.cairo(
                        fontSize: isMobile ? 11 : 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 14 : 16,
                      ),
                    ),
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 14),

        // Notes
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            labelStyle: GoogleFonts.cairo(fontSize: fontSize),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            isDense: true,
          ),
          style: GoogleFonts.cairo(fontSize: fontSize),
        ),
      ],
    );
  }

  List<Widget> _buildActions(bool isMobile) {
    return [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _canSubmit() ? _handleSubmit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.themeColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.themeColor.withValues(alpha: 0.4),
            padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'تأكيد التسليم',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 15 : 16,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildChoiceButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 12 : 14,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? widget.themeColor.withValues(alpha: 0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? widget.themeColor : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? widget.themeColor : Colors.grey.shade500,
                size: isMobile ? 20 : 22,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 15 : 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  color: selected ? widget.themeColor : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _faletQuantityError {
    if (_hasFalet != true) return null;
    final text = _faletQuantityController.text.trim();
    if (text.isEmpty) return null;
    final qty = int.tryParse(text);
    if (qty == null || qty <= 0) return null;
    final maxQty = widget.currentProduct?.packageQuantity ?? 0;
    if (maxQty > 0 && qty > maxQty) {
      return 'عدد عبوات الفالت يجب أن يكون بين 1 و $maxQty';
    }
    return null;
  }

  bool _canSubmit() {
    // Must have made an explicit choice
    if (widget.currentProduct != null && _hasFalet == null) return false;
    if (_hasFalet == true) {
      if (widget.currentProduct == null) return false;
      final qty = int.tryParse(_faletQuantityController.text) ?? 0;
      if (qty <= 0) return false;
      final maxQty = widget.currentProduct!.packageQuantity;
      if (maxQty > 0 && qty > maxQty) return false;
    }
    return true;
  }

  void _handleSubmit() {
    Navigator.of(context).pop(
      HandoverCreationResult(
        lastActiveProductTypeId: _hasFalet == true
            ? widget.currentProduct?.id
            : null,
        lastActiveProductFaletQuantity: _hasFalet == true
            ? int.tryParse(_faletQuantityController.text)
            : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}
