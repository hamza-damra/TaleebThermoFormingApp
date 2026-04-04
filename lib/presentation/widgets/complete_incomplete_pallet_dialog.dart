import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/received_incomplete_pallet.dart';

class CompleteIncompletePalletDialog extends StatefulWidget {
  final ReceivedIncompletePallet incompletePallet;
  final Color themeColor;

  const CompleteIncompletePalletDialog({
    super.key,
    required this.incompletePallet,
    required this.themeColor,
  });

  /// Returns null if cancelled, or the additionalFreshQuantity (0 if none).
  static Future<int?> show({
    required BuildContext context,
    required ReceivedIncompletePallet incompletePallet,
    required Color themeColor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => CompleteIncompletePalletDialog(
        incompletePallet: incompletePallet,
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<CompleteIncompletePalletDialog> createState() =>
      _CompleteIncompletePalletDialogState();
}

class _CompleteIncompletePalletDialogState
    extends State<CompleteIncompletePalletDialog> {
  bool _addFresh = false;
  final _freshController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _freshController.dispose();
    super.dispose();
  }

  int get _freshValue => int.tryParse(_freshController.text.trim()) ?? 0;
  int get _totalQuantity => widget.incompletePallet.quantity + _freshValue;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 440.0;

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
                  color: Colors.purple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.purple.shade600,
                  size: isMobile ? 36 : 44,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Title
              Text(
                'إكمال الطبلية الناقصة',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),

              // Pallet info
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      ProductType.formatCompactName(
                        widget.incompletePallet.productTypeName,
                      ),
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 6 : 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoChip(
                          'الكمية الحالية',
                          '${widget.incompletePallet.quantity}',
                          isMobile,
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 6 : 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        'مستلم من تسليم #${widget.incompletePallet.sourceHandoverId}',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget
                        .incompletePallet
                        .receivedAtDisplay
                        .isNotEmpty) ...[
                      SizedBox(height: isMobile ? 4 : 6),
                      Text(
                        widget.incompletePallet.receivedAtDisplay,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 20 : 24),

              // Add fresh toggle
              Row(
                children: [
                  Expanded(
                    child: _buildToggleButton(
                      label: 'إكمال كما هو',
                      isSelected: !_addFresh,
                      onTap: () => setState(() {
                        _addFresh = false;
                        _validationError = null;
                      }),
                      isMobile: isMobile,
                    ),
                  ),
                  SizedBox(width: isMobile ? 10 : 14),
                  Expanded(
                    child: _buildToggleButton(
                      label: 'إضافة عبوات جديدة',
                      isSelected: _addFresh,
                      onTap: () => setState(() {
                        _addFresh = true;
                      }),
                      isMobile: isMobile,
                      isHighlight: true,
                    ),
                  ),
                ],
              ),

              // Fresh quantity input
              if (_addFresh) ...[
                SizedBox(height: isMobile ? 16 : 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'عدد العبوات الجديدة الإضافية',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 6 : 8),
                    TextField(
                      controller: _freshController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'أدخل العدد',
                        hintStyle: GoogleFonts.cairo(
                          color: Colors.grey.shade400,
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
                            color: Colors.purple.shade300,
                            width: 2,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isMobile ? 12 : 16,
                          horizontal: 16,
                        ),
                      ),
                      onChanged: (_) {
                        setState(() => _validationError = null);
                      },
                    ),
                  ],
                ),
              ],
              SizedBox(height: isMobile ? 12 : 16),

              // Total display
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الكمية الإجمالية:',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      '$_totalQuantity',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Validation error
              if (_validationError != null) ...[
                SizedBox(height: isMobile ? 8 : 12),
                Container(
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
                ),
              ],
              SizedBox(height: isMobile ? 24 : 32),

              // Buttons
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
                        backgroundColor: Colors.purple.shade600,
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
                        'إكمال الطبلية',
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
    bool isHighlight = false,
  }) {
    final selectedColor = isHighlight
        ? Colors.purple.shade600
        : widget.themeColor;

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

  Widget _buildInfoChip(String label, String value, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 10 : 11,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void _handleConfirm() {
    if (_addFresh) {
      final freshQty = _freshValue;
      if (freshQty <= 0) {
        setState(() => _validationError = 'يرجى إدخال عدد صحيح أكبر من صفر');
        return;
      }
      Navigator.of(context).pop(freshQty);
    } else {
      Navigator.of(context).pop(0);
    }
  }
}
