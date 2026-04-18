import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/product_type.dart';
import '../../domain/entities/session_production_detail.dart';
import '../providers/palletizing_provider.dart';
import '../providers/printing_provider.dart';
import 'printer_selector_dialog.dart';

class ReprintByIdDialog extends StatefulWidget {
  const ReprintByIdDialog({super.key});

  @override
  State<ReprintByIdDialog> createState() => _ReprintByIdDialogState();
}

class _ReprintByIdDialogState extends State<ReprintByIdDialog> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  bool _isPrinting = false;
  bool _printDone = false;
  bool _printSuccess = false;
  String? _error;

  // Found pallet data
  SessionPalletDetail? _foundPallet;
  SessionProductTypeGroup? _foundGroup;
  int? _foundLineNumber;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'يرجى إدخال رقم الطبلية');
      return;
    }
    if (query.length != 12) {
      setState(() => _error = 'رقم الطبلية يجب أن يكون 12 رقم');
      return;
    }
    if (!RegExp(r'^\d{12}$').hasMatch(query)) {
      setState(() => _error = 'رقم الطبلية يجب أن يتكون من أرقام فقط');
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _foundPallet = null;
      _foundGroup = null;
      _foundLineNumber = null;
      _printDone = false;
    });

    final palletizingProvider = context.read<PalletizingProvider>();

    // Search both lines
    for (final lineNumber in [1, 2]) {
      try {
        final detail =
            await palletizingProvider.fetchSessionProductionDetail(lineNumber);
        for (final group in detail.groups) {
          for (final pallet in group.pallets) {
            if (pallet.scannedValue == query) {
              setState(() {
                _foundPallet = pallet;
                _foundGroup = group;
                _foundLineNumber = lineNumber;
                _isSearching = false;
              });
              return;
            }
          }
        }
      } catch (_) {
        // Line may not be authorized — skip
      }
    }

    setState(() {
      _isSearching = false;
      _error = 'لم يتم العثور على طبلية بهذا الرقم في المناوبة الحالية';
    });
  }

  Future<void> _print() async {
    if (_foundPallet == null || _foundLineNumber == null) return;

    final printingProvider = context.read<PrintingProvider>();

    if (!printingProvider.hasPrinters) {
      await showDialog(
        context: context,
        builder: (_) => const PrinterSelectorDialog(),
      );
      if (!mounted) return;
      if (!printingProvider.hasPrinters) {
        setState(() => _error = 'لم يتم إضافة طابعة');
        return;
      }
    }

    if (!printingProvider.hasSelectedPrinter) {
      await showDialog(
        context: context,
        builder: (_) => const PrinterSelectorDialog(),
      );
      if (!mounted) return;
      if (!printingProvider.hasSelectedPrinter) return;
    }

    setState(() {
      _isPrinting = true;
      _error = null;
    });

    // Look up full product type from bootstrap data for label content
    final palletizingProvider = context.read<PalletizingProvider>();
    final productType = _foundGroup != null
        ? palletizingProvider.productTypes
            .where((p) => p.id == _foundGroup!.productTypeId)
            .firstOrNull
        : null;

    // Top: productName (no sequence available for reprints)
    final topText = productType?.productName
        ?? (_foundGroup != null ? ProductType.formatCompactName(_foundGroup!.productTypeName) : null);

    // Bottom: description with fallback
    final description = productType?.description;
    final bottomText = (description != null && description.isNotEmpty)
        ? description
        : productType?.name ?? _foundGroup?.productTypeName;

    // Sides: scannedValue (lineLetter)
    final lineLetter = _foundLineNumber == 1 ? 'A' : 'B';
    final sideText = '${_foundPallet!.scannedValue} ($lineLetter)';

    final result = await printingProvider.print(
      scannedValue: _foundPallet!.scannedValue,
      copies: printingProvider.copies,
      topText: topText,
      bottomText: bottomText,
      sideText: sideText,
    );

    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      _printDone = true;
      _printSuccess = result.isSuccess;
      _error = result.isSuccess ? null : result.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.print_rounded,
                  size: 32, color: _primaryColor),
            ),
            const SizedBox(height: 12),
            Text(
              'إعادة طباعة ملصق',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'أدخل رقم الطبلية للبحث وطباعة الملصق',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),

            // Input
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              style: GoogleFonts.robotoMono(fontSize: 16),
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'رقم الطبلية',
                labelStyle: GoogleFonts.cairo(fontSize: 14),
                hintText: '0370000005',
                hintStyle: GoogleFonts.robotoMono(
                    fontSize: 14, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.qr_code_2_rounded,
                    color: _primaryColor),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                counterText: '',
              ),
              onSubmitted: (_) => _search(),
              enabled: !_isSearching && !_isPrinting,
            ),
            const SizedBox(height: 16),

            // Search button
            if (_foundPallet == null && !_printDone)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    _isSearching ? 'جاري البحث...' : 'بحث',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

            // Found pallet info + print
            if (_foundPallet != null && !_printDone) ...[
              _buildPalletInfo(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _print,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.print_rounded),
                  label: Text(
                    _isPrinting ? 'جاري الطباعة...' : 'طباعة الملصق',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            // Print result
            if (_printDone) ...[
              const SizedBox(height: 8),
              Icon(
                _printSuccess ? Icons.check_circle : Icons.error,
                color: _printSuccess ? Colors.green : Colors.red,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                _printSuccess ? 'تمت الطباعة بنجاح' : 'فشل في الطباعة',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _printSuccess ? Colors.green : Colors.red,
                ),
              ),
              if (!_printSuccess) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _printDone = false;
                        _error = null;
                      });
                      _print();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],

            // Error
            if (_error != null && !_printDone) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 20, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Close / new search
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('إغلاق',
                        style:
                            GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                  ),
                ),
                if (_printDone && _printSuccess) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _foundPallet = null;
                          _foundGroup = null;
                          _foundLineNumber = null;
                          _printDone = false;
                          _printSuccess = false;
                          _error = null;
                          _controller.clear();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('بحث جديد',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPalletInfo() {
    final indicator = _foundLineNumber == 1 ? 'A' : 'B';
    final lineName = _foundLineNumber == 1 ? 'خط الإنتاج 1' : 'خط الإنتاج 2';
    final lineColor = _foundLineNumber == 1
        ? const Color(0xFF1565C0)
        : const Color(0xFF388E3C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lineColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lineColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: lineColor),
              const SizedBox(width: 8),
              Text(
                'تم العثور على الطبلية',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: lineColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('رقم الطبلية', _foundPallet!.scannedValue),
          _infoRow('خط الإنتاج', '$lineName ($indicator)'),
          _infoRow('الكمية', '${_foundPallet!.quantity}'),
          _infoRow('تاريخ الإنشاء', _foundPallet!.createdAtDisplay),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}
