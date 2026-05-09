import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/pallet_create_response.dart';
import '../providers/palletizing_provider.dart';
import '../providers/printing_provider.dart';
import 'printer_selector_dialog.dart';
import 'product_type_image.dart';

class PalletSuccessDialog extends StatefulWidget {
  final PalletCreateResponse pallet;
  final Color lineColor;
  final int lineNumber;

  const PalletSuccessDialog({
    super.key,
    required this.pallet,
    required this.lineColor,
    required this.lineNumber,
  });

  @override
  State<PalletSuccessDialog> createState() => _PalletSuccessDialogState();
}

class _PalletSuccessDialogState extends State<PalletSuccessDialog> {
  bool _isPrinting = true;
  bool _printDone = false;
  bool _printSuccess = false;
  String? _printError;

  /// Before print completes: no X, no back, no outside dismiss.
  /// After print completes: allow close.
  bool get _canDismiss => _printDone;

  @override
  void initState() {
    super.initState();
    // Auto-print immediately after dialog appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePrint(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return PopScope(
      canPop: _canDismiss,
      child: AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: isMobile ? screenWidth * 0.9 : null,
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  _buildStatusIcon(),
                  const SizedBox(height: 16),
                  Text(
                    _printSuccess
                        ? 'تمت الطباعة بنجاح'
                        : _printError != null
                        ? 'فشل في الطباعة'
                        : _isPrinting
                        ? 'جاري الطباعة...'
                        : 'تم إنشاء الطبلية بنجاح',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.bold,
                      color: _printSuccess
                          ? Colors.green
                          : _printError != null
                          ? Colors.red
                          : widget.lineColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildProductTypeImage(isMobile),
                  const SizedBox(height: 16),
                  if (_printError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _printError!,
                              style: GoogleFonts.cairo(
                                color: Colors.red.shade700,
                                fontSize: isMobile ? 12 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildInfoRow(
                    'المنتج',
                    widget.pallet.productType.compactLabel,
                  ),
                  _buildInfoRow(
                    'الكمية',
                    '${widget.pallet.quantity} ${widget.pallet.productType.packageUnitDisplayName}',
                  ),
                  _buildInfoRow(
                    'خط الإنتاج',
                    widget.pallet.productionLine.name,
                  ),
                  _buildInfoRow('المشغل', widget.pallet.operator.name),
                  _buildInfoRow(
                    'التاريخ',
                    widget.pallet.createdAtDisplay,
                    showDivider: false,
                  ),
                  _buildPrinterInfo(),
                ],
              ),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: _buildActions(context),
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (_isPrinting) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: CircularProgressIndicator(strokeWidth: 4),
      );
    }
    if (_printSuccess) {
      return const Icon(Icons.print, color: Colors.green, size: 64);
    }
    if (_printError != null) {
      return const Icon(Icons.print_disabled, color: Colors.red, size: 64);
    }
    return const Icon(Icons.check_circle, color: Colors.green, size: 64);
  }

  Widget _buildProductTypeImage(bool isMobile) {
    final imageUrl = widget.pallet.productType.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageSize = isMobile ? 100.0 : 120.0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ProductTypeImage(
        imageUrl: imageUrl,
        size: imageSize,
        borderRadius: 12,
        showBorder: false,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildPrinterInfo() {
    return Consumer<PrintingProvider>(
      builder: (context, provider, _) {
        if (provider.selectedPrinter == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.print_outlined, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الطابعة النشطة: ${provider.selectedPrinter!.name}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    // After print failed: show retry + close buttons
    if (_printDone && _printError != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isPrinting ? null : () => _handleRetryPrint(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.lineColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: _isPrinting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 22),
              label: Text(
                'إعادة المحاولة',
                style: GoogleFonts.cairo(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.close, size: 22),
              label: Text(
                'إغلاق',
                style: GoogleFonts.cairo(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    // After print succeeded: show close button only
    if (_printDone) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.close, size: 22),
              label: Text(
                'إغلاق',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    // Auto-printing in progress — no action buttons, just spinner in the header
    return [];
  }

  Future<void> _handlePrint(BuildContext context) async {
    final printingProvider = context.read<PrintingProvider>();

    if (!printingProvider.hasPrinters) {
      await _showPrinterSelector(context);
      if (!context.mounted) return;
      if (!printingProvider.hasPrinters) {
        setState(() {
          _printDone = true;
          _printError = 'لم يتم إضافة طابعة';
        });
        return;
      }
    }

    if (!printingProvider.hasSelectedPrinter) {
      await _showPrinterSelector(context);
      if (!context.mounted) return;
      if (!printingProvider.hasSelectedPrinter) {
        return;
      }
    }

    setState(() {
      _isPrinting = true;
      _printError = null;
    });

    // Top: productName (sessionProductSequence) or just productName
    final seq = widget.pallet.sessionProductSequence;
    final topText = seq != null
        ? '${widget.pallet.productType.productName} ($seq)'
        : widget.pallet.productType.productName;

    // Bottom: description with fallback to full name
    final description = widget.pallet.productType.description;
    debugPrint('[LABEL DEBUG] productType.description = "$description"');
    debugPrint(
      '[LABEL DEBUG] productType.name = "${widget.pallet.productType.name}"',
    );
    debugPrint(
      '[LABEL DEBUG] productType.productName = "${widget.pallet.productType.productName}"',
    );
    debugPrint('[LABEL DEBUG] sessionProductSequence = $seq');
    final bottomText = (description != null && description.isNotEmpty)
        ? description
        : widget.pallet.productType.name;
    debugPrint('[LABEL DEBUG] resolved bottomText = "$bottomText"');
    debugPrint('[LABEL DEBUG] resolved topText = "$topText"');

    // Sides: scannedValue (lineLetter)
    final lineLetter = widget.lineNumber == 1 ? 'A' : 'B';
    final sideText = '${widget.pallet.scannedValue} ($lineLetter)';
    debugPrint('[LABEL DEBUG] resolved sideText = "$sideText"');

    final result = await printingProvider.print(
      scannedValue: widget.pallet.scannedValue,
      copies: printingProvider.copies,
      topText: topText,
      bottomText: bottomText,
      sideText: sideText,
    );

    if (!mounted) return;
    if (!context.mounted) return;

    final palletizingProvider = context.read<PalletizingProvider>();
    await palletizingProvider.logPrintAttempt(
      lineNumber: widget.lineNumber,
      palletId: widget.pallet.palletId,
      printerIdentifier: printingProvider.selectedPrinter?.name ?? 'UNKNOWN',
      success: result.isSuccess,
      failureReason: result.errorMessage,
    );

    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      _printDone = true;
      _printSuccess = result.isSuccess;
      _printError = result.isSuccess ? null : result.errorMessage;
    });
  }

  Future<void> _handleRetryPrint(BuildContext context) async {
    setState(() {
      _printDone = false;
      _printSuccess = false;
      _printError = null;
    });
    await _handlePrint(context);
  }

  Future<void> _showPrinterSelector(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => const PrinterSelectorDialog(),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool showDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }
}
