import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';

class ProductSwitchDialog extends StatefulWidget {
  final ProductType previousProduct;
  final ProductType newProduct;
  final Color themeColor;

  const ProductSwitchDialog({
    super.key,
    required this.previousProduct,
    required this.newProduct,
    required this.themeColor,
  });

  /// Returns null if cancelled, 0 if no loose balance, or the loose count.
  static Future<int?> show({
    required BuildContext context,
    required ProductType previousProduct,
    required ProductType newProduct,
    required Color themeColor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => ProductSwitchDialog(
        previousProduct: previousProduct,
        newProduct: newProduct,
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<ProductSwitchDialog> createState() => _ProductSwitchDialogState();
}

class _ProductSwitchDialogState extends State<ProductSwitchDialog> {
  bool _hasLoose = false;
  final _looseController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _looseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 420.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
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
              // Icon
              Container(
                padding: EdgeInsets.all(isMobile ? 14 : 18),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.orange.shade700,
                  size: isMobile ? 36 : 44,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Title
              Text(
                'تبديل نوع المنتج',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),

              // Info
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 16,
                    color: Colors.grey.shade700,
                  ),
                  children: [
                    const TextSpan(text: 'سيتم التبديل من '),
                    TextSpan(
                      text: widget.previousProduct.productName,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                    ),
                    const TextSpan(text: ' إلى '),
                    TextSpan(
                      text: widget.newProduct.productName,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.previousProduct.description != null &&
                  widget.previousProduct.description!.trim().isNotEmpty) ...
                [
                  SizedBox(height: isMobile ? 4 : 6),
                  Text(
                    widget.previousProduct.description!,
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              if (widget.newProduct.description != null &&
                  widget.newProduct.description!.trim().isNotEmpty) ...
                [
                  SizedBox(height: isMobile ? 4 : 6),
                  Text(
                    '→ ${widget.newProduct.description!}',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              SizedBox(height: isMobile ? 20 : 28),

              // Question
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 14 : 18),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'هل يوجد فالت من المنتج السابق؟',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Yes/No toggle
              Row(
                children: [
                  Expanded(
                    child: _buildToggleButton(
                      label: 'لا يوجد فالت',
                      isSelected: !_hasLoose,
                      onTap: () => setState(() {
                        _hasLoose = false;
                        _validationError = null;
                      }),
                      isMobile: isMobile,
                    ),
                  ),
                  SizedBox(width: isMobile ? 10 : 14),
                  Expanded(
                    child: _buildToggleButton(
                      label: 'نعم يوجد فالت',
                      isSelected: _hasLoose,
                      onTap: () => setState(() {
                        _hasLoose = true;
                      }),
                      isMobile: isMobile,
                      isWarning: true,
                    ),
                  ),
                ],
              ),

              // Loose count input (if yes)
              if (_hasLoose) ...[
                SizedBox(height: isMobile ? 16 : 20),
                TextField(
                  controller: _looseController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'عدد العبوات الفالتة',
                    labelStyle: GoogleFonts.cairo(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.grey.shade600,
                    ),
                    errorText: _validationError,
                    errorStyle: GoogleFonts.cairo(fontSize: isMobile ? 12 : 13),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.orange.shade400,
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: isMobile ? 14 : 18,
                      horizontal: 16,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {
                      _validationError = _computeValidationError();
                    });
                  },
                ),
              ],
              SizedBox(height: isMobile ? 24 : 32),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.5,
                        ),
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
                    child: ElevatedButton(
                      onPressed: _handleConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'تأكيد التبديل',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isMobile,
    bool isWarning = false,
  }) {
    final selectedColor = isWarning ? Colors.orange : widget.themeColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isMobile ? 12 : 16,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 13 : 15,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? selectedColor : Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String? _computeValidationError() {
    if (!_hasLoose) return null;
    final text = _looseController.text.trim();
    if (text.isEmpty) return null;
    final count = int.tryParse(text);
    if (count == null || count <= 0) return null;
    final maxQty = widget.previousProduct.packageQuantity;
    if (maxQty > 0 && count > maxQty) {
      return 'عدد عبوات الفالت يجب أن يكون بين 1 و $maxQty';
    }
    return null;
  }

  void _handleConfirm() {
    if (!_hasLoose) {
      Navigator.of(context).pop(0);
      return;
    }

    final text = _looseController.text.trim();
    if (text.isEmpty) {
      setState(() => _validationError = 'يرجى إدخال عدد العبوات الفالتة');
      return;
    }

    final count = int.tryParse(text);
    if (count == null || count <= 0) {
      setState(() => _validationError = 'يرجى إدخال رقم صحيح أكبر من صفر');
      return;
    }

    final maxQty = widget.previousProduct.packageQuantity;
    if (maxQty > 0 && count > maxQty) {
      setState(() => _validationError = 'عدد عبوات الفالت يجب أن يكون بين 1 و $maxQty');
      return;
    }

    Navigator.of(context).pop(count);
  }
}
