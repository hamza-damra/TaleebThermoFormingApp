import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/constants/grinding_recommendation_strings.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/pallet_label_content.dart';
import '../../domain/entities/palletizing_line.dart';
import '../../domain/entities/session_production_detail.dart';
import '../providers/palletizing_provider.dart';
import 'grinding_chip.dart';
import 'line_scoped_route.dart';
import '../providers/printing_provider.dart';
import 'printer_selector_dialog.dart';

class SessionDrilldownDialog extends StatefulWidget {
  final PalletizingLine line;

  const SessionDrilldownDialog({super.key, required this.line});

  static Future<void> show({
    required BuildContext context,
    required PalletizingLine line,
  }) {
    return showDialog(
      context: context,
      builder: (_) => LineScopedRoute(
        lineId: line.lineId,
        child: SessionDrilldownDialog(line: line),
      ),
    );
  }

  @override
  State<SessionDrilldownDialog> createState() => _SessionDrilldownDialogState();
}

class _SessionDrilldownDialogState extends State<SessionDrilldownDialog> {
  SessionProductionDetail? _detail;

  /// Mirrors [_detail] for the reprint dialog, which sits on its own route and
  /// must print what the latest read says (grinding marker, reprint block).
  final ValueNotifier<SessionProductionDetail?> _latestDetail = ValueNotifier(
    null,
  );
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLineNotAuthorized = false;

  late final PalletizingProvider _provider;
  late int _sessionRevision;

  /// Bumped per request; only the latest request's response is applied, so a
  /// slow read started before a newer one can never overwrite it.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _provider = context.read<PalletizingProvider>();
    _sessionRevision = _provider.sessionDataRevision(widget.line.lineId);
    _provider.addListener(_onProviderChanged);
    _loadData();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _latestDetail.dispose();
    super.dispose();
  }

  /// The shift summary behind this dialog changed (a pallet was created,
  /// cancelled or edited while it is open) — re-read the detail in place so
  /// both views keep showing the same backend state.
  void _onProviderChanged() {
    final revision = _provider.sessionDataRevision(widget.line.lineId);
    if (revision == _sessionRevision) return;
    _sessionRevision = revision;
    if (_isLineNotAuthorized) return;
    _loadData(silent: _detail != null);
  }

  /// [silent] keeps the current list on screen while re-reading, and keeps it
  /// if the re-read fails.
  Future<void> _loadData({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isLineNotAuthorized = false;
      });
    }

    try {
      final detail = await _provider.fetchSessionProductionDetail(
        widget.line.lineId,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
        _errorMessage = null;
      });
      _latestDetail.value = detail;
    } on ApiException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (e.code == 'LINE_NOT_AUTHORIZED') {
        setState(() {
          _isLoading = false;
          _isLineNotAuthorized = true;
        });
      } else if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.displayMessage;
        });
      }
    } catch (e) {
      if (!mounted || seq != _loadSeq || silent) return;
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
      builder: (_) => _ReprintDialog(
        pallet: pallet,
        group: group,
        line: widget.line,
        latestDetail: _latestDetail,
      ),
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
      // The tile paints its ink on the nearest Material; without this one it
      // would be the dialog's, hidden under this container's white fill.
      child: Material(
        type: MaterialType.transparency,
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
              context.watch<PalletizingProvider>().productDisplayName(
                productTypeId: group.productTypeId,
                backendName: group.productTypeName,
              ),
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
              Divider(
                height: 1,
                color: widget.line.color.withValues(alpha: 0.1),
              ),
              ...group.pallets.map(
                (pallet) => _buildPalletRow(pallet, group, isMobile),
              ),
            ],
          ),
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
          // Pallet number
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pallet.palletNumber,
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
                if (_nonBlank(pallet.grindingStatusLabel) case final status?)
                  Padding(
                    padding: EdgeInsets.only(top: isMobile ? 2 : 4),
                    child: GrindingChip(
                      key: Key('grindingStatusChip-${pallet.palletId}'),
                      text: status,
                      fontSize: isMobile ? 10 : 11,
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
          // Reprint button — greyed once grinding started or finished; the
          // dialog it opens explains why and keeps printing disabled.
          SizedBox(
            width: isMobile ? 44 : 52,
            child: IconButton(
              key: Key('reprintPallet-${pallet.palletId}'),
              onPressed: () => _showReprintDialog(pallet, group),
              icon: Icon(
                pallet.isLabelReprintAllowed
                    ? Icons.print_rounded
                    : Icons.print_disabled_rounded,
                color: pallet.isLabelReprintAllowed
                    ? widget.line.color
                    : Colors.grey.shade400,
                size: isMobile ? 20 : 24,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: pallet.isLabelReprintAllowed
                  ? 'إعادة طباعة'
                  : GrindingRecommendationStrings.reprintBlocked,
            ),
          ),
        ],
      ),
    );
  }
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

// ── Reprint Status Dialog ──

class _ReprintDialog extends StatefulWidget {
  final SessionPalletDetail pallet;
  final SessionProductTypeGroup group;
  final PalletizingLine line;

  /// The drill-down's latest read. The pallet is re-resolved from it, so a
  /// grinding change while this dialog is open (recommended, approved,
  /// rejected, started) reaches the printed label.
  final ValueListenable<SessionProductionDetail?> latestDetail;

  const _ReprintDialog({
    required this.pallet,
    required this.group,
    required this.line,
    required this.latestDetail,
  });

  @override
  State<_ReprintDialog> createState() => _ReprintDialogState();
}

class _ReprintDialogState extends State<_ReprintDialog> {
  bool _isPrinting = false;
  bool _printSuccess = false;
  String? _printError;

  late SessionPalletDetail _pallet = widget.pallet;

  @override
  void initState() {
    super.initState();
    widget.latestDetail.addListener(_onLatestDetail);
  }

  @override
  void dispose() {
    widget.latestDetail.removeListener(_onLatestDetail);
    super.dispose();
  }

  void _onLatestDetail() {
    final groups = widget.latestDetail.value?.groups ?? const [];
    for (final group in groups) {
      for (final pallet in group.pallets) {
        if (pallet.palletId == _pallet.palletId) {
          if (mounted) setState(() => _pallet = pallet);
          return;
        }
      }
    }
    // Gone from the read (e.g. voided) — keep the last known copy.
  }

  bool get _reprintBlocked => !_pallet.isLabelReprintAllowed;

  Future<void> _handlePrint() async {
    if (_reprintBlocked) return;
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
    final productType = palletizingProvider.productTypeById(
      widget.group.productTypeId,
    );

    final labelContent = PalletLabelContentMapper.fromSessionPallet(
      pallet: _pallet,
      group: widget.group,
      productType: productType,
      lineNumber: widget.line.lineNumber,
    );

    final result = await printingProvider.print(
      labelContent: labelContent,
      copies: printingProvider.copies,
    );

    if (!mounted) return;

    await palletizingProvider.logPrintAttempt(
      lineId: widget.line.lineId,
      palletId: _pallet.palletId,
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
                  if (_reprintBlocked && !_printSuccess) ...[
                    SizedBox(height: isMobile ? 12 : 16),
                    _buildErrorBanner(
                      isMobile,
                      GrindingRecommendationStrings.reprintBlocked,
                      key: const Key('reprintBlockedByGrindingBanner'),
                    ),
                  ] else if (_printError != null) ...[
                    SizedBox(height: isMobile ? 12 : 16),
                    _buildErrorBanner(isMobile, _printError!),
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
    if (_reprintBlocked) {
      return Icon(Icons.print_disabled, color: Colors.grey, size: size);
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
            context.watch<PalletizingProvider>().productDisplayName(
              productTypeId: widget.group.productTypeId,
              backendName: widget.group.productTypeName,
            ),
            isMobile,
          ),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('رقم الطبلية', _pallet.palletNumber, isMobile),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('الكمية', '${_pallet.quantity} عبوة', isMobile),
          Divider(height: 16, color: widget.line.color.withValues(alpha: 0.1)),
          _buildInfoLine('التاريخ', _pallet.createdAtDisplay, isMobile),
          if (_nonBlank(_pallet.grindingStatusLabel) case final status?) ...[
            Divider(
              height: 16,
              color: widget.line.color.withValues(alpha: 0.1),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GrindingChip(text: status),
            ),
          ],
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

  Widget _buildErrorBanner(bool isMobile, String message, {Key? key}) {
    return Container(
      key: key,
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
              message,
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
        key: const Key('sessionReprintPrintButton'),
        onPressed: _isPrinting || _reprintBlocked ? null : _handlePrint,
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
