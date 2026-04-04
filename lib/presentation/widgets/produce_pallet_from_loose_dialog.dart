import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/loose_balance_item.dart';
import '../../domain/entities/product_type.dart';

class ProducePalletFromLooseDialog extends StatefulWidget {
  final LooseBalanceItem looseBalance;
  final int packageQuantity;
  final Color themeColor;

  const ProducePalletFromLooseDialog({
    super.key,
    required this.looseBalance,
    required this.packageQuantity,
    required this.themeColor,
  });

  /// Returns null if cancelled, or a map with looseQuantityToUse and freshQuantityToAdd.
  static Future<Map<String, int>?> show({
    required BuildContext context,
    required LooseBalanceItem looseBalance,
    required int packageQuantity,
    required Color themeColor,
  }) {
    return showDialog<Map<String, int>>(
      context: context,
      builder: (context) => ProducePalletFromLooseDialog(
        looseBalance: looseBalance,
        packageQuantity: packageQuantity,
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<ProducePalletFromLooseDialog> createState() =>
      _ProducePalletFromLooseDialogState();
}

class _ProducePalletFromLooseDialogState
    extends State<ProducePalletFromLooseDialog> {
  late final TextEditingController _looseController;
  final _freshController = TextEditingController(text: '0');
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _looseController = TextEditingController(
      text: widget.looseBalance.loosePackageCount.toString(),
    );
  }

  @override
  void dispose() {
    _looseController.dispose();
    _freshController.dispose();
    super.dispose();
  }

  int get _looseValue => int.tryParse(_looseController.text.trim()) ?? 0;
  int get _freshValue => int.tryParse(_freshController.text.trim()) ?? 0;
  int get _totalQuantity => _looseValue + _freshValue;

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
                  color: widget.themeColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: widget.themeColor,
                  size: isMobile ? 36 : 44,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Title
              Text(
                'إنشاء طبلية من الفالت',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),

              // Product info
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: widget.themeColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.themeColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      ProductType.formatCompactName(
                        widget.looseBalance.productTypeName,
                      ),
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoChip(
                          'الرصيد المتاح',
                          '${widget.looseBalance.loosePackageCount}',
                          isMobile,
                        ),
                        SizedBox(width: isMobile ? 8 : 12),
                        _buildInfoChip(
                          'حجم الطبلية',
                          '${widget.packageQuantity}',
                          isMobile,
                        ),
                      ],
                    ),
                    if (widget.looseBalance.isFromHandover) ...[
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
                          'من تسليم سابق',
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 11 : 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 20 : 24),

              // Loose quantity input
              _buildInputField(
                controller: _looseController,
                label: 'عدد العبوات الفالتة للاستخدام',
                hint: 'أدخل العدد',
                isMobile: isMobile,
              ),
              SizedBox(height: isMobile ? 14 : 18),

              // Fresh quantity input
              _buildInputField(
                controller: _freshController,
                label: 'عبوات جديدة إضافية (اختياري)',
                hint: '0',
                isMobile: isMobile,
              ),
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
                        color: widget.themeColor,
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
                        'إنشاء الطبلية',
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 13 : 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 18 : 22,
            fontWeight: FontWeight.bold,
            color: widget.themeColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400),
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
              vertical: isMobile ? 12 : 16,
              horizontal: 16,
            ),
          ),
          onChanged: (_) {
            setState(() => _validationError = null);
          },
        ),
      ],
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
    final looseQty = _looseValue;
    final freshQty = _freshValue;

    if (looseQty <= 0) {
      setState(() => _validationError = 'يرجى إدخال عدد صحيح أكبر من صفر');
      return;
    }

    if (looseQty > widget.looseBalance.loosePackageCount) {
      setState(
        () => _validationError =
            'الكمية المطلوبة ($looseQty) أكبر من الرصيد المتاح (${widget.looseBalance.loosePackageCount})',
      );
      return;
    }

    if (freshQty < 0) {
      setState(
        () => _validationError = 'الكمية الإضافية لا يمكن أن تكون سالبة',
      );
      return;
    }

    Navigator.of(
      context,
    ).pop({'looseQuantityToUse': looseQty, 'freshQuantityToAdd': freshQty});
  }
}
