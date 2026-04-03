import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import 'searchable_picker_dialog.dart';

class CreatePalletDialog extends StatefulWidget {
  final ProductionLine line;
  final List<ProductType> productTypes;
  final ProductType? initialProductType;

  const CreatePalletDialog({
    super.key,
    required this.line,
    required this.productTypes,
    this.initialProductType,
  });

  @override
  State<CreatePalletDialog> createState() => _CreatePalletDialogState();
}

class _CreatePalletDialogState extends State<CreatePalletDialog> {
  late ProductType? _selectedProductType;
  int _quantity = 20;
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _selectedProductType = widget.initialProductType;
    _quantityController = TextEditingController(text: '$_quantity');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 400.0;
    final spacing = isMobile ? 16.0 : 20.0;

    return AlertDialog(
      title: Text(
        'إنشاء مشتاح جديد - ${widget.line.arabicLabel}',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: widget.line.color,
          fontSize: isMobile ? 16 : 20,
        ),
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 24),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProductDropdown(context),
            SizedBox(height: spacing),
            _buildQuantityStepper(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'إلغاء',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _canConfirm() ? _handleConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.line.color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 32,
              vertical: isMobile ? 8 : 12,
            ),
          ),
          child: Text(
            'تأكيد',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductDropdown(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع المنتج',
          style: GoogleFonts.cairo(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        InkWell(
          onTap: () async {
            final selected = await SearchablePickerDialog.show<ProductType>(
              context: context,
              title: 'اختر نوع المنتج',
              searchHint: 'ابحث عن المنتج...',
              items: widget.productTypes,
              selectedItem: _selectedProductType,
              displayTextExtractor: (pt) => pt.name,
              searchMatcher: (pt, query) {
                final queryLower = query.toLowerCase();
                return pt.name.toLowerCase().contains(queryLower) ||
                    pt.productName.toLowerCase().contains(queryLower) ||
                    pt.color.toLowerCase().contains(queryLower) ||
                    pt.prefix.toLowerCase().contains(queryLower) ||
                    pt.displayLabel.toLowerCase().contains(queryLower);
              },
              themeColor: widget.line.color,
            );
            if (selected != null) {
              setState(() {
                _selectedProductType = selected;
              });
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 14 : 16,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedProductType?.name ?? 'اختر نوع المنتج',
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      color: _selectedProductType != null
                          ? Colors.black87
                          : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityStepper(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 16.0;
    final iconSize = isMobile ? 32.0 : 40.0;
    final quantityFontSize = isMobile ? 22.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الكمية',
          style: GoogleFonts.cairo(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _quantity > 1
                    ? () {
                        setState(() {
                          _quantity--;
                          _quantityController.text = '$_quantity';
                        });
                      }
                    : null,
                icon: Icon(
                  Icons.remove_circle,
                  color: widget.line.color,
                  size: iconSize,
                ),
              ),
              SizedBox(width: isMobile ? 8 : 16),
              SizedBox(
                width: isMobile ? 60 : 80,
                child: TextField(
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.cairo(
                    fontSize: quantityFontSize,
                    fontWeight: FontWeight.bold,
                    color: widget.line.color,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  controller: _quantityController,
                  onChanged: (value) {
                    if (value.isEmpty) return;
                    final newValue = int.tryParse(value);
                    if (newValue != null && newValue >= 0) {
                      _quantity = newValue;
                    }
                  },
                ),
              ),
              SizedBox(width: isMobile ? 8 : 16),
              IconButton(
                onPressed: () {
                  setState(() {
                    _quantity++;
                    _quantityController.text = '$_quantity';
                  });
                },
                icon: Icon(
                  Icons.add_circle,
                  color: widget.line.color,
                  size: iconSize,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _canConfirm() {
    return _selectedProductType != null && _quantity > 0;
  }

  void _handleConfirm() {
    Navigator.of(context).pop({
      'productType': _selectedProductType,
      'quantity': _quantity,
    });
  }
}
