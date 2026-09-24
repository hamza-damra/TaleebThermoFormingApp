import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/grinding_recommendation_strings.dart';
import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/pallet_label.dart';
import '../../domain/entities/pallet_label_content.dart';
import '../providers/palletizing_provider.dart';
import '../providers/printing_provider.dart';
import 'grinding_chip.dart';
import 'printer_selector_dialog.dart';

class ReprintByIdDialog extends StatefulWidget {
  const ReprintByIdDialog({super.key});

  @override
  State<ReprintByIdDialog> createState() => _ReprintByIdDialogState();
}

class _ReprintByIdDialogState extends State<ReprintByIdDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  bool _isPrinting = false;
  bool _printDone = false;
  bool _printSuccess = false;
  String? _error;

  /// The resolved label from the backend, cleared after print + reset.
  PalletLabel? _label;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Resets all transient state for a new search.
  void _reset() {
    setState(() {
      _label = null;
      _isLoading = false;
      _isPrinting = false;
      _printDone = false;
      _printSuccess = false;
      _error = null;
      _controller.clear();
    });
  }

  // ── Client-side validation ──

  String? _validateLocally(String input) {
    if (input.isEmpty) return 'يرجى إدخال رقم الطبلية';
    if (!RegExp(r'^\d+$').hasMatch(input)) {
      return 'رقم الطبلية يجب أن يحتوي على أرقام فقط';
    }
    if (input.length != 12) {
      return 'رقم الطبلية يجب أن يكون 12 رقماً';
    }
    return null;
  }

  // ── Search (fetch label from backend) ──

  Future<void> _search() async {
    // Guard re-entry (double-tap).
    if (_isLoading || _isPrinting) return;

    final query = _controller.text.trim();
    final localError = _validateLocally(query);
    if (localError != null) {
      setState(() => _error = localError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _label = null;
      _printDone = false;
    });

    final provider = context.read<PalletizingProvider>();

    try {
      final label = await provider.fetchPalletLabel(query);

      if (!mounted) return;

      setState(() {
        _label = label;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      final refusal = switch (e.code) {
        'PALLET_LABEL_REPRINT_NOT_AVAILABLE' =>
          'هذه الطبلية ملغاة، ولا يمكن إعادة طباعة ملصقها.',
        'PALLET_BLOCKED_BY_GRINDING' =>
          GrindingRecommendationStrings.reprintBlocked,
        _ => null,
      };
      if (refusal != null) {
        setState(() => _isLoading = false);
        await _showReprintRefusedDialog(refusal);
        if (!mounted) return;
        _reset();
        return;
      }

      setState(() {
        _isLoading = false;
        _error = _mapApiError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'تعذّر الاتصال بالخادم. حاول مرة أخرى.';
      });
    }
  }

  String _mapApiError(ApiException e) {
    switch (e.code) {
      case 'PALLET_NOT_FOUND':
        return 'لا توجد طبلية بهذا الرقم. تأكد من الرقم المطبوع على الطبلية.';
      case 'INVALID_SCANNED_VALUE_LENGTH':
        return 'رقم الطبلية يجب أن يكون 12 رقماً';
      case 'INVALID_SCANNED_VALUE_NON_NUMERIC':
        return 'رقم الطبلية يجب أن يحتوي على أرقام فقط';
      case 'INVALID_SCANNED_VALUE_FORMAT':
        return 'يرجى إدخال رقم الطبلية';
      case 'DEVICE_KEY_INVALID':
        return 'الجهاز غير مصرّح له. راجع الإدارة.';
      case 'NETWORK_ERROR':
      case 'TIMEOUT_ERROR':
        return 'تعذّر الاتصال بالخادم. حاول مرة أخرى.';
      default:
        return e.displayMessage;
    }
  }

  // ── Reprint refused (409: cancelled pallet / grinding started) ──

  Future<void> _showReprintRefusedDialog(String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تعذّرت إعادة الطباعة',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.cairo(fontSize: 15, height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'حسناً',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Print ──

  /// `false` once the pallet's grinding started or finished (backend flag;
  /// absent on an older backend = allowed).
  bool get _labelReprintAllowed => _label?.labelReprintAllowed ?? true;

  Future<void> _print() async {
    if (_label == null || _isPrinting || !_labelReprintAllowed) return;

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

    final label = _label!;
    final palletizingProvider = context.read<PalletizingProvider>();
    final productType = label.productTypeId == null
        ? null
        : palletizingProvider.productTypes
              .where((item) => item.id == label.productTypeId)
              .firstOrNull;
    // Resolve the pallet's line number (rendered line, or the last number
    // seen for that lineId) so the side band carries the same letter the
    // original print used, not the backend's long snapshot name.
    final lineNumber = label.productionLineId == null
        ? null
        : palletizingProvider.lineNumberForLineId(label.productionLineId!);
    final labelContent = PalletLabelContentMapper.fromResolvedLabel(
      label,
      productType: productType,
      lineNumber: lineNumber,
    );

    final result = await printingProvider.print(
      labelContent: labelContent,
      copies: printingProvider.copies,
    );

    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      _printDone = true;
      _printSuccess = result.isSuccess;
      _error = result.isSuccess ? null : result.errorMessage;
    });

    if (result.isSuccess) {
      // Show snackbar outside the dialog.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إعادة الطباعة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
                child: const Icon(
                  Icons.print_rounded,
                  size: 32,
                  color: _primaryColor,
                ),
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
                  hintText: '12 رقماً',
                  hintStyle: GoogleFonts.robotoMono(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: const Icon(
                    Icons.qr_code_2_rounded,
                    color: _primaryColor,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _primaryColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  counterText: '',
                ),
                onChanged: (_) {
                  // Clear error on keystroke so the worker sees fresh feedback.
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
                onSubmitted: (_) => _search(),
                enabled: !_isLoading && !_isPrinting,
              ),
              const SizedBox(height: 16),

              // Search / print button
              if (_label == null && !_printDone)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _search,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(
                      _isLoading ? 'جارٍ التحميل…' : 'بحث',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              // Found pallet info + print
              if (_label != null && !_printDone) ...[
                _buildPalletInfo(),
                if (!_labelReprintAllowed) ...[
                  const SizedBox(height: 12),
                  _buildReprintBlockedBanner(),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('reprintByIdPrintButton'),
                    onPressed: _isPrinting || !_labelReprintAllowed
                        ? null
                        : _print,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.print_rounded),
                    label: Text(
                      _isPrinting ? 'جاري الطباعة...' : 'إعادة طباعة الملصق',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                  _printSuccess ? 'تمت إعادة الطباعة' : 'فشل في الطباعة',
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
                        // Retry re-prints from the label already in memory —
                        // no second fetch needed.
                        setState(() {
                          _printDone = false;
                          _error = null;
                        });
                        _print();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        'إعادة المحاولة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: Colors.red.shade700,
                      ),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'إغلاق',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_printDone && _printSuccess) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _reset,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'بحث جديد',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
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
    final label = _label!;
    final lineColor = _primaryColor;

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
          _infoRow('رقم الطبلية', label.scannedValue),
          _infoRow(
            'المنتج',
            context.watch<PalletizingProvider>().productDisplayName(
              productTypeId: label.productTypeId,
              backendName: label.productTypeName,
            ),
          ),
          _infoRow('خط الإنتاج', label.productionLineName),
          _infoRow('المشغل', label.operatorName),
          _infoRow('الكمية', '${label.quantity}'),
          _infoRow('تاريخ الإنشاء', label.createdAtDisplay),
          if (_grindingMarkerText(label) case final marker?) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GrindingChip(text: marker),
            ),
          ],
        ],
      ),
    );
  }

  /// The marker the label will carry, exactly as the backend sent it.
  String? _grindingMarkerText(PalletLabel label) {
    if (label.grindingRecommended != true) return null;
    final text = label.grindingLabelText?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Widget _buildReprintBlockedBanner() {
    return Container(
      key: const Key('reprintBlockedByGrindingBanner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 20, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              GrindingRecommendationStrings.reprintBlocked,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
          ),
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
            style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade700),
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
