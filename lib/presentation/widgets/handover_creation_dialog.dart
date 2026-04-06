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
  bool _hasFalet = false;
  final _faletQuantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  @override
  void dispose() {
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
        ],
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 20),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: _buildForm(isMobile),
        ),
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

        // FALET toggle
        Container(
          decoration: BoxDecoration(
            color: _hasFalet
                ? widget.themeColor.withValues(alpha: 0.08)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hasFalet
                  ? widget.themeColor.withValues(alpha: 0.4)
                  : Colors.grey.shade300,
            ),
          ),
          child: SwitchListTile(
            value: _hasFalet,
            onChanged: (v) => setState(() {
              _hasFalet = v;
              if (!v) _faletQuantityController.text = '1';
            }),
            title: Text(
              'هل يوجد فالت للمنتج النشط؟',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 14 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeTrackColor: widget.themeColor.withValues(alpha: 0.5),
            thumbColor: WidgetStatePropertyAll(widget.themeColor),
            dense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: 2,
            ),
          ),
        ),

        // FALET quantity input
        if (_hasFalet) ...[
          const SizedBox(height: 14),
          TextFormField(
            controller: _faletQuantityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'كمية الفالت (عدد العبوات)',
              labelStyle: GoogleFonts.cairo(fontSize: fontSize),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
            ),
            style: GoogleFonts.cairo(fontSize: fontSize),
          ),
        ],
        const SizedBox(height: 14),

        // Notes
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            labelStyle: GoogleFonts.cairo(fontSize: fontSize),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
      ),
      ElevatedButton(
        onPressed: _canSubmit() ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.themeColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.themeColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          'تأكيد التسليم',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }

  bool _canSubmit() {
    if (_hasFalet) {
      if (widget.currentProduct == null) return false;
      final qty = int.tryParse(_faletQuantityController.text) ?? 0;
      if (qty <= 0) return false;
    }
    return true;
  }

  void _handleSubmit() {
    Navigator.of(context).pop(
      HandoverCreationResult(
        lastActiveProductTypeId: _hasFalet
            ? widget.currentProduct?.id
            : null,
        lastActiveProductFaletQuantity: _hasFalet
            ? int.tryParse(_faletQuantityController.text)
            : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}
