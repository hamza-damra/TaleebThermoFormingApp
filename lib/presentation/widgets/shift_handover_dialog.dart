import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart' as entity;

class HandoverItemEntry {
  entity.ProductionLine? productionLine;
  ProductType? productType;
  int quantity;
  String? scannedValue;
  String? notes;

  HandoverItemEntry({
    this.productionLine,
    this.productType,
    this.quantity = 1,
    this.scannedValue,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'productionLineId': productionLine!.id,
    'productTypeId': productType!.id,
    'quantity': quantity,
    if (scannedValue != null && scannedValue!.isNotEmpty)
      'scannedValue': scannedValue,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };
}

class ShiftHandoverDialog extends StatefulWidget {
  final List<ProductType> productTypes;
  final List<entity.ProductionLine> productionLines;
  final Color themeColor;

  const ShiftHandoverDialog({
    super.key,
    required this.productTypes,
    required this.productionLines,
    required this.themeColor,
  });

  @override
  State<ShiftHandoverDialog> createState() => _ShiftHandoverDialogState();
}

class _ShiftHandoverDialogState extends State<ShiftHandoverDialog> {
  final List<HandoverItemEntry> _items = [HandoverItemEntry()];

  List<entity.ProductionLine> _availableLines(HandoverItemEntry currentItem) {
    final selectedIds = _items
        .where((item) => item != currentItem && item.productionLine != null)
        .map((item) => item.productionLine!.id)
        .toSet();
    return widget.productionLines
        .where((line) => !selectedIds.contains(line.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 500.0;

    return AlertDialog(
      title: Text(
        'تسليم المناوبة - مشاتيح غير مكتملة',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: widget.themeColor,
          fontSize: isMobile ? 15 : 18,
        ),
      ),
      contentPadding: EdgeInsets.all(isMobile ? 12 : 20),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'أدخل المشاتيح غير المكتملة التي تريد تسليمها للمناوبة القادمة:',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 13 : 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              ..._items.asMap().entries.map(
                (entry) => _buildItemCard(entry.key, entry.value, isMobile),
              ),
              const SizedBox(height: 8),
              if (_items.length < 2)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _items.add(HandoverItemEntry());
                    });
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    'إضافة عنصر',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.themeColor,
                    side: BorderSide(color: widget.themeColor),
                  ),
                ),
            ],
          ),
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
            backgroundColor: widget.themeColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 32,
              vertical: isMobile ? 8 : 12,
            ),
          ),
          child: Text(
            'تأكيد التسليم',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(int index, HandoverItemEntry item, bool isMobile) {
    final fontSize = isMobile ? 13.0 : 14.0;
    final availableLines = _availableLines(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'عنصر ${index + 1}',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize,
                      color: widget.themeColor,
                    ),
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _items.removeAt(index);
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<entity.ProductionLine>(
              value: item.productionLine,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'خط الإنتاج',
                labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isMobile ? 10 : 12,
                ),
                isDense: true,
              ),
              hint: Text(
                'اختر خط الإنتاج',
                style: GoogleFonts.cairo(fontSize: fontSize),
              ),
              items: availableLines.map((line) {
                return DropdownMenuItem<entity.ProductionLine>(
                  value: line,
                  child: Text(
                    line.name,
                    style: GoogleFonts.cairo(fontSize: fontSize),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  item.productionLine = value;
                });
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ProductType>(
              value: item.productType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'نوع المنتج',
                labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isMobile ? 10 : 12,
                ),
                isDense: true,
              ),
              hint: Text(
                'اختر نوع المنتج',
                style: GoogleFonts.cairo(fontSize: fontSize),
              ),
              items: widget.productTypes.map((pt) {
                return DropdownMenuItem<ProductType>(
                  value: pt,
                  child: Text(
                    pt.name,
                    style: GoogleFonts.cairo(fontSize: fontSize),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  item.productType = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${item.quantity}',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الكمية',
                      labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 10 : 12,
                      ),
                      isDense: true,
                    ),
                    style: GoogleFonts.cairo(fontSize: fontSize),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed >= 1) {
                        item.quantity = parsed;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: item.scannedValue,
                    decoration: InputDecoration(
                      labelText: 'كود المشتاح (اختياري)',
                      labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 10 : 12,
                      ),
                      isDense: true,
                    ),
                    style: GoogleFonts.cairo(fontSize: fontSize),
                    textDirection: TextDirection.ltr,
                    onChanged: (value) {
                      item.scannedValue = value;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: item.notes,
              decoration: InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isMobile ? 10 : 12,
                ),
                isDense: true,
              ),
              style: GoogleFonts.cairo(fontSize: fontSize),
              onChanged: (value) {
                item.notes = value;
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _canConfirm() {
    return _items.isNotEmpty &&
        _items.every(
          (item) =>
              item.productionLine != null &&
              item.productType != null &&
              item.quantity >= 1,
        );
  }

  void _handleConfirm() {
    final items = _items.map((item) => item.toJson()).toList();
    Navigator.of(context).pop(items);
  }
}
