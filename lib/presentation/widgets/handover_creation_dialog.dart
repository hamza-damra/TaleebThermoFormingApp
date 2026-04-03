import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import 'searchable_picker_dialog.dart';

/// Result returned from the handover creation dialog.
class HandoverCreationResult {
  final int? incompletePalletProductTypeId;
  final int? incompletePalletQuantity;
  final List<Map<String, dynamic>> looseBalances;
  final String? notes;

  const HandoverCreationResult({
    this.incompletePalletProductTypeId,
    this.incompletePalletQuantity,
    this.looseBalances = const [],
    this.notes,
  });
}

/// A single loose balance row in the handover form.
class _LooseBalanceEntry {
  ProductType? productType;
  final TextEditingController countController;

  _LooseBalanceEntry()
      : countController = TextEditingController(text: '1');

  void dispose() => countController.dispose();
}

enum _HandoverCase { none, incompletePalletOnly, looseBalancesOnly, both }

class HandoverCreationDialog extends StatefulWidget {
  final List<ProductType> productTypes;
  final Color themeColor;

  const HandoverCreationDialog({
    super.key,
    required this.productTypes,
    required this.themeColor,
  });

  /// Show the dialog and return the result, or null if cancelled.
  static Future<HandoverCreationResult?> show({
    required BuildContext context,
    required List<ProductType> productTypes,
    required Color themeColor,
  }) {
    return showDialog<HandoverCreationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HandoverCreationDialog(
        productTypes: productTypes,
        themeColor: themeColor,
      ),
    );
  }

  @override
  State<HandoverCreationDialog> createState() =>
      _HandoverCreationDialogState();
}

class _HandoverCreationDialogState extends State<HandoverCreationDialog> {
  // Step 0: ask questions, Step 1: form
  int _step = 0;

  // Step 0 answers
  bool _hasIncompletePallet = false;
  bool _hasLooseBalances = false;

  // Step 1 form fields
  ProductType? _selectedProductType;
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  // Loose balance rows
  final List<_LooseBalanceEntry> _looseBalanceEntries = [];
  String? _looseBalanceError;

  _HandoverCase get _selectedCase {
    if (_hasIncompletePallet && _hasLooseBalances) return _HandoverCase.both;
    if (_hasIncompletePallet) return _HandoverCase.incompletePalletOnly;
    if (_hasLooseBalances) return _HandoverCase.looseBalancesOnly;
    return _HandoverCase.none;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    for (final entry in _looseBalanceEntries) {
      entry.dispose();
    }
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
          child: _step == 0 ? _buildStep0(isMobile) : _buildStep1(isMobile),
        ),
      ),
      actions: _step == 0 ? _buildStep0Actions(isMobile) : _buildStep1Actions(isMobile),
    );
  }

  // ── Step 0: Ask questions ──

  Widget _buildStep0(bool isMobile) {
    final fontSize = isMobile ? 14.0 : 15.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'حدد ما إذا كان هناك عناصر معلقة قبل التسليم:',
          style: GoogleFonts.cairo(fontSize: fontSize, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        _buildToggleTile(
          label: 'هل يوجد مشاتيح ناقصة؟',
          value: _hasIncompletePallet,
          onChanged: (v) => setState(() => _hasIncompletePallet = v),
          isMobile: isMobile,
        ),
        const SizedBox(height: 10),
        _buildToggleTile(
          label: 'هل يوجد فالت؟',
          value: _hasLooseBalances,
          onChanged: (v) => setState(() => _hasLooseBalances = v),
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildToggleTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: value ? widget.themeColor.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? widget.themeColor.withValues(alpha: 0.4) : Colors.grey.shade300,
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          label,
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
    );
  }

  List<Widget> _buildStep0Actions(bool isMobile) {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
      ),
      ElevatedButton(
        onPressed: () {
          if (_selectedCase == _HandoverCase.none) {
            // Clean handover — go directly to notes-only step
            setState(() => _step = 1);
          } else {
            setState(() => _step = 1);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.themeColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text('التالي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      ),
    ];
  }

  // ── Step 1: Form based on selected case ──

  Widget _buildStep1(bool isMobile) {
    final fontSize = isMobile ? 13.0 : 14.0;
    final showPalletForm =
        _selectedCase == _HandoverCase.incompletePalletOnly ||
        _selectedCase == _HandoverCase.both;
    final showLooseForm =
        _selectedCase == _HandoverCase.looseBalancesOnly ||
        _selectedCase == _HandoverCase.both;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Case indicator
        _buildCaseChip(isMobile),
        const SizedBox(height: 16),

        // Incomplete pallet form
        if (showPalletForm) ...[
          _buildSectionHeader('مشتاح ناقص', Icons.inventory_2_outlined, isMobile),
          const SizedBox(height: 10),
          _buildProductTypePicker(fontSize, isMobile),
          const SizedBox(height: 10),
          TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'الكمية',
              labelStyle: GoogleFonts.cairo(fontSize: fontSize),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
            style: GoogleFonts.cairo(fontSize: fontSize),
          ),
          const SizedBox(height: 14),
        ],

        // Loose balances dynamic form
        if (showLooseForm) ...[
          _buildSectionHeader('أرصدة المواد الفرطة', Icons.warning_amber_rounded, isMobile),
          const SizedBox(height: 8),
          _buildLooseBalanceForm(fontSize, isMobile),
          const SizedBox(height: 14),
        ],

        // Notes — always shown
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            labelStyle: GoogleFonts.cairo(fontSize: isMobile ? 13.0 : 14.0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
          style: GoogleFonts.cairo(fontSize: isMobile ? 13.0 : 14.0),
        ),
      ],
    );
  }

  // ── Loose balance dynamic form ──

  Widget _buildLooseBalanceForm(double fontSize, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Existing rows
        for (int i = 0; i < _looseBalanceEntries.length; i++)
          _buildLooseBalanceRow(i, fontSize, isMobile),

        // Error message
        if (_looseBalanceError != null) ...[
          const SizedBox(height: 6),
          Text(
            _looseBalanceError!,
            style: GoogleFonts.cairo(fontSize: 11, color: Colors.red.shade700),
          ),
        ],

        // Add row button
        if (_looseBalanceEntries.length < 50) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _looseBalanceEntries.add(_LooseBalanceEntry());
                _looseBalanceError = null;
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              'إضافة نوع منتج',
              style: GoogleFonts.cairo(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.themeColor,
              side: BorderSide(color: widget.themeColor.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
            ),
          ),
        ],

        // Info when no rows added yet
        if (_looseBalanceEntries.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'اضغط "إضافة نوع منتج" لإضافة أرصدة المواد الفرطة.',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLooseBalanceRow(int index, double fontSize, bool isMobile) {
    final entry = _looseBalanceEntries[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 10 : 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row with remove button
            Row(
              children: [
                Expanded(
                  child: Text(
                    'نوع ${index + 1}',
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _looseBalanceEntries[index].dispose();
                      _looseBalanceEntries.removeAt(index);
                      _looseBalanceError = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Product type picker
            InkWell(
              onTap: () async {
                final selected = await SearchablePickerDialog.show<ProductType>(
                  context: context,
                  title: 'اختر نوع المنتج',
                  searchHint: 'ابحث عن المنتج...',
                  items: widget.productTypes,
                  selectedItem: entry.productType,
                  displayTextExtractor: (pt) => pt.name,
                  searchMatcher: (pt, query) {
                    final queryLower = query.toLowerCase();
                    return pt.name.toLowerCase().contains(queryLower) ||
                        pt.productName.toLowerCase().contains(queryLower) ||
                        pt.color.toLowerCase().contains(queryLower) ||
                        pt.prefix.toLowerCase().contains(queryLower) ||
                        pt.displayLabel.toLowerCase().contains(queryLower);
                  },
                  themeColor: widget.themeColor,
                );
                if (selected != null) {
                  setState(() {
                    entry.productType = selected;
                    _looseBalanceError = null;
                  });
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: isMobile ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.productType?.name ?? 'اختر نوع المنتج',
                        style: GoogleFonts.cairo(
                          fontSize: fontSize,
                          color: entry.productType != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Count input
            TextFormField(
              controller: entry.countController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'عدد العبوات',
                labelStyle: GoogleFonts.cairo(fontSize: fontSize),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                isDense: true,
              ),
              style: GoogleFonts.cairo(fontSize: fontSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaseChip(bool isMobile) {
    String label;
    IconData icon;
    switch (_selectedCase) {
      case _HandoverCase.none:
        label = 'تسليم نظيف — بدون عناصر معلقة';
        icon = Icons.check_circle_outline;
      case _HandoverCase.incompletePalletOnly:
        label = 'مشاتيح ناقصة فقط';
        icon = Icons.inventory_2_outlined;
      case _HandoverCase.looseBalancesOnly:
        label = 'فالت فقط';
        icon = Icons.warning_amber_rounded;
      case _HandoverCase.both:
        label = 'مشاتيح ناقصة وفالت';
        icon = Icons.assignment_outlined;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: widget.themeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.themeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: widget.themeColor, size: isMobile ? 18 : 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: widget.themeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isMobile) {
    return Row(
      children: [
        Icon(icon, size: isMobile ? 18 : 20, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 14 : 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildProductTypePicker(double fontSize, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع المنتج',
          style: GoogleFonts.cairo(fontSize: fontSize, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
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
              themeColor: widget.themeColor,
            );
            if (selected != null) {
              setState(() => _selectedProductType = selected);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: isMobile ? 12 : 14,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
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
                          : Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStep1Actions(bool isMobile) {
    return [
      TextButton(
        onPressed: () => setState(() => _step = 0),
        child: Text('رجوع', style: GoogleFonts.cairo(color: Colors.grey)),
      ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          'تأكيد التسليم',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
    ];
  }

  bool _canSubmit() {
    final needsPallet =
        _selectedCase == _HandoverCase.incompletePalletOnly ||
        _selectedCase == _HandoverCase.both;
    if (needsPallet) {
      if (_selectedProductType == null) return false;
      final qty = int.tryParse(_quantityController.text) ?? 0;
      if (qty <= 0) return false;
    }

    final needsLoose =
        _selectedCase == _HandoverCase.looseBalancesOnly ||
        _selectedCase == _HandoverCase.both;
    if (needsLoose) {
      if (_looseBalanceEntries.isEmpty) return false;
      for (final entry in _looseBalanceEntries) {
        if (entry.productType == null) return false;
        final count = int.tryParse(entry.countController.text) ?? 0;
        if (count <= 0) return false;
      }
    }

    return true;
  }

  void _handleSubmit() {
    final needsPallet =
        _selectedCase == _HandoverCase.incompletePalletOnly ||
        _selectedCase == _HandoverCase.both;
    final needsLoose =
        _selectedCase == _HandoverCase.looseBalancesOnly ||
        _selectedCase == _HandoverCase.both;

    // Validate no duplicate product types in loose balances
    if (needsLoose && _looseBalanceEntries.isNotEmpty) {
      final productTypeIds = <int>{};
      for (final entry in _looseBalanceEntries) {
        if (entry.productType != null) {
          if (!productTypeIds.add(entry.productType!.id)) {
            setState(() => _looseBalanceError = 'لا يمكن تكرار نفس نوع المنتج في قائمة الفالت');
            return;
          }
        }
      }
    }

    // Build loose balances list
    final looseBalances = <Map<String, dynamic>>[];
    if (needsLoose) {
      for (final entry in _looseBalanceEntries) {
        looseBalances.add({
          'productTypeId': entry.productType!.id,
          'loosePackageCount': int.parse(entry.countController.text),
        });
      }
    }

    Navigator.of(context).pop(
      HandoverCreationResult(
        incompletePalletProductTypeId: needsPallet ? _selectedProductType?.id : null,
        incompletePalletQuantity:
            needsPallet ? int.tryParse(_quantityController.text) : null,
        looseBalances: looseBalances,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}
