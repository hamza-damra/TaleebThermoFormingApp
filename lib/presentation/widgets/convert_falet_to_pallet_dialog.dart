import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/product_type.dart';

class ConvertFaletToPalletDialog extends StatefulWidget {
  final FaletItem faletItem;
  final Color themeColor;

  const ConvertFaletToPalletDialog({
    super.key,
    required this.faletItem,
    required this.themeColor,
  });

  /// Returns null if cancelled, or the additionalFreshQuantity (0 if none).
  static Future<int?> show({
    required BuildContext context,
    required FaletItem faletItem,
    required Color themeColor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => ConvertFaletToPalletDialog(
        faletItem: faletItem,
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<ConvertFaletToPalletDialog> createState() =>
      _ConvertFaletToPalletDialogState();
}

class _ConvertFaletToPalletDialogState
    extends State<ConvertFaletToPalletDialog> {
  bool _addFresh = false;
  final _freshController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _freshController.dispose();
    super.dispose();
  }

  int get _freshValue => int.tryParse(_freshController.text.trim()) ?? 0;
  int get _totalQuantity => widget.faletItem.quantity + _freshValue;

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
                  Icons.check_circle_outline_rounded,
                  color: widget.themeColor,
                  size: isMobile ? 36 : 44,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Title
              Text(
                'تحويل الفالت إلى طبلية',
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
                        widget.faletItem.productTypeName,
                      ),
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Container(
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
                            'كمية الفالت',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 10 : 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '${widget.faletItem.quantity}',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Add fresh toggle
              Container(
                decoration: BoxDecoration(
                  color: _addFresh
                      ? widget.themeColor.withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _addFresh
                        ? widget.themeColor.withValues(alpha: 0.4)
                        : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  value: _addFresh,
                  onChanged: (v) => setState(() {
                    _addFresh = v;
                    if (!v) _freshController.clear();
                    _validationError = null;
                  }),
                  title: Text(
                    'إضافة كمية جديدة؟',
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

              // Fresh quantity input
              if (_addFresh) ...[
                SizedBox(height: isMobile ? 14 : 18),
                TextField(
                  controller: _freshController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: widget.themeColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'الكمية الجديدة الإضافية',
                    labelStyle: GoogleFonts.cairo(
                      fontSize: isMobile ? 14 : 16,
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
                  onChanged: (_) {
                    setState(() => _validationError = null);
                  },
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
                        'تحويل لطبلية',
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

  void _handleConfirm() {
    final freshQty = _addFresh ? _freshValue : 0;

    if (_addFresh && freshQty <= 0) {
      setState(
        () => _validationError = 'يرجى إدخال كمية إضافية أكبر من صفر',
      );
      return;
    }

    Navigator.of(context).pop(freshQty);
  }
}
