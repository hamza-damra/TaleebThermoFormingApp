import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/session_production_detail.dart';
import '../providers/palletizing_provider.dart';
import '../providers/printing_provider.dart';
import 'printer_selector_dialog.dart';

class SessionDrilldownDialog extends StatefulWidget {
  final ProductionLine line;

  const SessionDrilldownDialog({super.key, required this.line});

  static Future<void> show({
    required BuildContext context,
    required ProductionLine line,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SessionDrilldownDialog(line: line),
    );
  }

  @override
  State<SessionDrilldownDialog> createState() => _SessionDrilldownDialogState();
}

class _SessionDrilldownDialogState extends State<SessionDrilldownDialog> {
  SessionProductionDetail? _detail;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLineNotAuthorized = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isLineNotAuthorized = false;
    });

    try {
      final provider = context.read<PalletizingProvider>();
      final detail = await provider.fetchSessionProductionDetail(
        widget.line.number,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'LINE_NOT_AUTHORIZED') {
        setState(() {
          _isLoading = false;
          _isLineNotAuthorized = true;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = e.displayMessage;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل في تحميل البيانات';
      });
    }
  }

  void _showReprintDialog(
    SessionPalletDetail pallet,
    SessionProductTypeGroup group,
  ) {
    showDialog(
      context: context,
      builder: (_) =>
          _ReprintDialog(pallet: pallet, group: group, line: widget.line),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 40,
        vertical: isMobile ? 24 : 40,
      ),
      child: Container(
        width: isMobile ? screenSize.width : 600,
        constraints: BoxConstraints(maxHeight: screenSize.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isMobile),
            Flexible(child: _buildBody(isMobile)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 14 : 18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.line.color,
            widget.line.color.withValues(alpha: 0.85),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMobile ? 16 : 20),
          topRight: Radius.circular(isMobile ? 16 : 20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.list_alt_rounded,
              color: Colors.white,
              size: isMobile ? 20 : 24,
            ),
          ),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Text(
              'تفاصيل إنتاج المناوبة',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            iconSize: isMobile ? 22 : 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isMobile) {
    if (_isLoading) {
      return _buildLoadingState(isMobile);
    }

    if (_isLineNotAuthorized) {
      // Auto-dismiss after showing the message briefly
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا يوجد مشغل مصرح على هذا الخط',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
      return _buildLoadingState(isMobile);
    }

    if (_errorMessage != null) {
      return _buildErrorState(isMobile);
    }

    final detail = _detail;
    if (detail == null || detail.groups.isEmpty) {
      return _buildEmptyState(isMobile);
    }

    return _buildGroupsList(detail, isMobile);
  }

  Widget _buildLoadingState(bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 32 : 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: widget.line.color),
          SizedBox(height: isMobile ? 16 : 20),
          Text(
            'جاري تحميل البيانات...',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade400,
            size: isMobile ? 40 : 48,
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            _errorMessage ?? 'حدث خطأ',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 16 : 20),
          ElevatedButton.icon(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.line.color,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 24 : 32,
                vertical: isMobile ? 12 : 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(Icons.refresh_rounded, size: isMobile ? 18 : 20),
            label: Text(
              'إعادة المحاولة',
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 32 : 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            color: Colors.grey.shade300,
            size: isMobile ? 48 : 56,
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            'لا توجد طبليات في هذه المناوبة',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 15 : 17,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsList(SessionProductionDetail detail, bool isMobile) {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      itemCount: detail.groups.length,
      itemBuilder: (context, index) {
        final group = detail.groups[index];
        return _buildGroupTile(group, isMobile, initiallyExpanded: index == 0);
      },
    );
  }

  Widget _buildGroupTile(
    SessionProductTypeGroup group,
    bool isMobile, {
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.line.color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 14 : 18,
            vertical: isMobile ? 4 : 6,
          ),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: widget.line.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: widget.line.color,
              size: isMobile ? 20 : 24,
            ),
          ),
          title: Text(
            ProductType.formatCompactName(group.productTypeName),
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            '${group.completedPalletCount} طبلية',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 12 : 14,
              color: widget.line.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconColor: widget.line.color,
          collapsedIconColor: widget.line.color,
          children: [
            Divider(height: 1, color: widget.line.color.withValues(alpha: 0.1)),
            ...group.pallets.map(
              (pallet) => _buildPalletRow(pallet, group, isMobile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPalletRow(
    SessionPalletDetail pallet,
    SessionProductTypeGroup group,
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 18,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Serial number
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pallet.serialNumber,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(height: isMobile ? 2 : 4),
                Text(
                  '${pallet.quantity} عبوة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11 : 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Created at
          Expanded(
            flex: 2,
            child: Text(
              pallet.createdAtDisplay,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 11 : 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Reprint button
          SizedBox(
            width: isMobile ? 44 : 52,
            child: IconButton(
              onPressed: () => _showReprintDialog(pallet, group),
              icon: Icon(
                Icons.print_rounded,
                color: widget.line.color,
                size: isMobile ? 20 : 24,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'إعادة طباعة',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reprint Status Dialog ──

class _ReprintDialog extends StatefulWidget {
  final SessionPalletDetail pallet;
  final SessionProductTypeGroup group;
  final ProductionLine line;

  const _ReprintDialog({
    required this.pallet,
    required this.group,
    required this.line,
  });

  @override
  State<_ReprintDialog> createState() => _ReprintDialogState();
}

class _ReprintDialogState extends State<_ReprintDialog> {
  bool _isPrinting = false;
  bool _printSuccess = false;
  String? _printError;

  Future<void> _handlePrint() async {
    final printingProvider = context.read<PrintingProvider>();

    if (!printingProvider.hasPrinters) {
      await _showPrinterSelector();
      if (!mounted) return;
      if (!printingProvider.hasPrinters) {
        setState(() => _printError = 'لم يتم إضافة طابعة');
        return;
      }
    }

    if (!printingProvider.hasSelectedPrinter) {
      await _showPrinterSelector();
      if (!mounted) return;
      if (!printingProvider.hasSelectedPrinter) return;
    }

    setState(() {
      _isPrinting = true;
      _printError = null;
    });

    // Look up full product type from bootstrap data for label content
    final palletizingProvider = context.read<PalletizingProvider>();
    final productType = palletizingProvider.productTypes
        .where((p) => p.id == widget.group.productTypeId)
        .firstOrNull;

    // Top: productName (no sequence available for reprints)
    final topText =
        productType?.productName ??
        ProductType.formatCompactName(widget.group.productTypeName);

    // Bottom: description with fallback
    final description = productType?.description;
    final bottomText = (description != null && description.isNotEmpty)
        ? description
        : productType?.name ?? widget.group.productTypeName;

    // Sides: scannedValue (lineLetter)
    final lineLetter = widget.line.number == 1 ? 'A' : 'B';
    final sideText = '${widget.pallet.scannedValue} ($lineLetter)';

    final result = await printingProvider.print(
      scannedValue: widget.pallet.scannedValue,
      copies: printingProvider.copies,
      topText: topText,
      bottomText: bottomText,
      sideText: sideText,
    );

    if (!mounted) return;

    await palletizingProvider.logPrintAttempt(
      lineNumber: widget.line.number,
      palletId: widget.pallet.palletId,
      printerIdentifier: printingProvider.selectedPrinter?.name ?? 'UNKNOWN',
      success: result.isSuccess,
      failureReason: result.errorMessage,
    );

    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      if (result.isSuccess) {
        _printSuccess = true;
        _printError = null;
      } else {
        _printError = result.errorMessage;
      }
    });
  }

  Future<void> _showPrinterSelector() async {
    await showDialog(
      context: context,
      builder: (context) => const PrinterSelectorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: isMobile ? MediaQuery.of(context).size.width * 0.85 : 380,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  _buildStatusIcon(isMobile),
                  SizedBox(height: isMobile ? 16 : 20),
                  Text(
                    _printSuccess ? 'تمت الطباعة بنجاح' : 'إعادة طباعة الملصق',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: _printSuccess ? Colors.green : widget.line.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isMobile ? 16 : 20),
                  _buildPalletInfo(isMobile),
                  if (_printError != null) ...[
                    SizedBox(height: isMobile ? 12 : 16),
                    _buildErrorBanner(isMobile),
                  ],
                  SizedBox(height: isMobile ? 12 : 16),
                  _buildPrinterInfo(isMobile),
                  SizedBox(height: isMobile ? 20 : 24),
                  if (!_printSuccess) _buildPrintButton(isMobile),
                  if (_printSuccess) _buildDoneButton(isMobile),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.grey),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(bool isMobile) {
    final size = isMobile ? 52.0 : 64.0;
    if (_isPrinting) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 3.5,
          color: widget.line.color,
        ),
      );
    }
    if (_printSuccess) {
      return Icon(Icons.print, color: Colors.green, size: size);
    }
    if (_printError != null) {
      return Icon(Icons.print_disabled, color: Colors.red, size: size);
    }
    return Icon(Icons.print_rounded, color: widget.line.color, size: size);
  }

  Widget _buildPalletInfo(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: widget.line.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.line.color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          _buildInfoLine(
            'المنتج',
            ProductType.formatCompactName(widget.group.productTypeName),
            isMobile,
          ),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('رقم الطبلية', widget.pallet.serialNumber, isMobile),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('الكمية', '${widget.pallet.quantity} عبوة', isMobile),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('التاريخ', widget.pallet.createdAtDisplay, isMobile),
        ],
      ),
    );
  }

  Widget _buildInfoLine(String label, String value, bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 12 : 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: isMobile ? 18 : 20,
          ),
          SizedBox(width: isMobile ? 8 : 10),
          Expanded(
            child: Text(
              _printError!,
              style: GoogleFonts.cairo(
                color: Colors.red.shade700,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterInfo(bool isMobile) {
    return Consumer<PrintingProvider>(
      builder: (context, provider, _) {
        final printer = provider.selectedPrinter;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 8 : 10),
          decoration: BoxDecoration(
            color: printer != null
                ? Colors.blue.withValues(alpha: 0.05)
                : Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: printer != null
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                printer != null
                    ? Icons.print_outlined
                    : Icons.print_disabled_outlined,
                size: isMobile ? 16 : 18,
                color: printer != null ? Colors.blue : Colors.orange,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Expanded(
                child: Text(
                  printer != null
                      ? 'الطابعة: ${printer.name}'
                      : 'لم يتم اختيار طابعة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: printer != null
                        ? Colors.blue.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ),
              if (printer == null)
                TextButton(
                  onPressed: _showPrinterSelector,
                  child: Text(
                    'اختيار',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.bold,
                      color: widget.line.color,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrintButton(bool isMobile) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isPrinting ? null : _handlePrint,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.line.color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.line.color.withValues(alpha: 0.5),
          padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        icon: _isPrinting
            ? SizedBox(
                width: isMobile ? 20 : 24,
                height: isMobile ? 20 : 24,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.print_rounded, size: isMobile ? 22 : 26),
        label: Text(
          _printError != null ? 'إعادة المحاولة' : 'طباعة الملصق',
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildDoneButton(bool isMobile) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green,
          side: const BorderSide(color: Colors.green, width: 1.5),
          padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'تم',
          style: GoogleFonts.cairo(
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
