import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/falet_resolution_entry.dart';
import '../../domain/entities/handover_falet_action.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart' as entity;
import '../providers/palletizing_provider.dart';
import 'create_pallet_dialog.dart';
import 'handover_creation_dialog.dart';
import 'handover_confirm_dialog.dart';
import 'handover_reject_dialog.dart';
import 'line_context_strip.dart';
import 'line_handover_card.dart';
import 'pallet_success_dialog.dart';
import 'palletizer_pin_screen.dart';
import 'falet_screen.dart';
import 'session_table_widget.dart';
import 'thermoforming_waiting_card.dart';

class ProductionLineSection extends StatelessWidget {
  final ProductionLine line;
  final entity.ProductionLine? productionLineEntity;

  const ProductionLineSection({
    super.key,
    required this.line,
    this.productionLineEntity,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final horizontalPadding = isMobile ? 16.0 : 24.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final uiState = provider.getUiState(line.number);
    final isHandoverReview = uiState == LineUiState.pendingHandoverReview;

    return Stack(
      children: [
        Container(
          color: line.lightColor,
          child: SafeArea(
            top: false,
            child: isHandoverReview
                ? _buildHandoverReviewLayout(
                    context,
                    provider,
                    isMobile,
                    horizontalPadding,
                    bottomPadding,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: isMobile ? 20 : 32),
                                if (ResponsiveHelper.isDesktop(context)) ...[
                                  _buildHeader(context),
                                  const SizedBox(height: 32),
                                ],
                                _buildTopActionButtons(
                                  context,
                                  provider,
                                  isMobile,
                                ),
                                _buildFormCard(context),
                                SizedBox(height: isMobile ? 20 : 28),
                                if (provider
                                        .getPendingHandover(line.number)
                                        ?.isPending ??
                                    false) ...[
                                  LineHandoverCard(
                                    line: line,
                                    handover: provider.getPendingHandover(
                                      line.number,
                                    )!,
                                    showResolveActions: false,
                                    onResolve: () =>
                                        _handleConfirmHandover(context),
                                    onReject: () =>
                                        _handleRejectHandover(context),
                                  ),
                                  SizedBox(height: isMobile ? 20 : 28),
                                ],
                                _buildSessionTable(context),
                                SizedBox(height: isMobile ? 24 : 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            isMobile ? 12 : 16,
                            horizontalPadding,
                            (isMobile ? 12 : 16) + bottomPadding,
                          ),
                          child: _buildCreateButton(context),
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        // Per-line state overlays. Existing blocked / handover-incoming /
        // handover-review states still take precedence over the new waiting
        // / palletizer-PIN overlays — the waiting card never masks a real
        // failure mode.
        if (uiState == LineUiState.waitingForThermoforming)
          ThermoformingWaitingCard(line: line),
        if (uiState == LineUiState.needsPalletizerAuth)
          PalletizerPinScreen(line: line),
      ],
    );
  }

  Widget _buildHandoverReviewLayout(
    BuildContext context,
    PalletizingProvider provider,
    bool isMobile,
    double horizontalPadding,
    double bottomPadding,
  ) {
    final handover = provider.getPendingHandover(line.number);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: isMobile ? 20 : 32),
                  // Review header
                  Container(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade600,
                          Colors.orange.shade400,
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.rate_review_rounded,
                          color: Colors.white,
                          size: isMobile ? 28 : 34,
                        ),
                        SizedBox(width: isMobile ? 12 : 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مراجعة التسليم',
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'راجع تفاصيل التسليم ثم قم بالتأكيد أو الرفض',
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 12 : 14,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isMobile ? 20 : 28),
                  // Full handover detail card
                  if (handover != null)
                    LineHandoverCard(
                      line: line,
                      handover: handover,
                      showResolveActions: true,
                      onResolve: () => _handleConfirmHandover(context),
                      onReject: () => _handleRejectHandover(context),
                    )
                  else
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(isMobile ? 24 : 32),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            SizedBox(height: isMobile ? 12 : 16),
                            Text(
                              'جاري تحميل تفاصيل التسليم...',
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 14 : 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(height: isMobile ? 24 : 32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [line.color, line.color.withValues(alpha: 0.85)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: line.color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        productionLineEntity?.name ?? line.arabicLabel,
        textAlign: TextAlign.center,
        style: GoogleFonts.cairo(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: line.color.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 28),
        child: LineContextStrip(line: line),
      ),
    );
  }

  Widget _buildTopActionButtons(
    BuildContext context,
    PalletizingProvider provider,
    bool isMobile,
  ) {
    final showOpenItems =
        provider.isLineAuthorized(line.number) &&
        !provider.isLineBlocked(line.number);
    final showHandover = provider.canInitiateHandover(line.number);

    if (!showOpenItems && !showHandover) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      child: Row(
        children: [
          // فالت — RIGHT side (first in RTL Row = right visually)
          if (showOpenItems)
            Expanded(
              child: _AnimatedFaletButton(
                line: line,
                isMobile: isMobile,
                hasOpenFalet: provider.hasOpenFalet(line.number),
                openFaletCount: provider.getOpenFaletCount(line.number),
              ),
            ),
          if (showOpenItems && showHandover)
            SizedBox(width: isMobile ? 10 : 14),
          // تسليم مناوبة — LEFT side (second in RTL Row = left visually)
          if (showHandover)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _handleCreateHandover(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: Icon(Icons.swap_horiz_rounded, size: isMobile ? 18 : 20),
                label: Text(
                  'تسليم مناوبة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionTable(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final sessionRows = provider.getSessionTable(line.number);

    return SessionTableWidget(line: line, rows: sessionRows);
  }

  Widget _buildCreateButton(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final isBlocked = provider.isLineBlocked(line.number);
    final isCreating = provider.isLineCreating(line.number);

    return ElevatedButton(
      onPressed: (isCreating || isBlocked)
          ? null
          : () => _showCreateDialog(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: line.color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: line.color.withValues(alpha: 0.5),
        minimumSize: Size(double.infinity, isMobile ? 60 : 68),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: isCreating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: isMobile ? 22 : 26,
                ),
                SizedBox(width: isMobile ? 8 : 12),
                Text(
                  'إنشاء طبلية جديدة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 18 : 21,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final provider = context.read<PalletizingProvider>();

    // Hard block: pallet creation is not allowed while open FALET exists on the
    // line. FALET is owned by the Thermoforming Operator App.
    if (provider.hasOpenFalet(line.number)) {
      _showFaletBlockedMessage(context);
      return;
    }

    final initialProductType = provider.getSelectedProductType(line.number);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreatePalletDialog(
        line: line,
        initialProductType: initialProductType,
      ),
    );

    if (result == null || !context.mounted) return;

    final productType = result['productType'] as ProductType;
    final quantity = result['quantity'] as int;

    try {
      final palletResponse = await provider.createPallet(
        lineNumber: line.number,
        productTypeId: productType.id,
        quantity: quantity,
      );
      if (context.mounted) {
        _showSuccessDialog(context, palletResponse);
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // Race-safety: server says FALET appeared between our local check and
      // the create call. Same hard-block message — FALET is operator-owned.
      if (e.code == 'FALET_MUST_BE_CONSUMED_FIRST') {
        _showFaletBlockedMessage(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في إنشاء الطبلية', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFaletBlockedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'يوجد فالت مفتوح، يجب على المشغّل معالجته من تطبيق التشكيل الحراري',
          style: GoogleFonts.cairo(),
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, dynamic palletResponse) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PalletSuccessDialog(
        pallet: palletResponse,
        lineColor: line.color,
        lineNumber: line.number,
      ),
    );
  }

  Future<void> _handleCreateHandover(BuildContext context) async {
    final provider = context.read<PalletizingProvider>();

    // ── Step 1: Show handover creation dialog FIRST ──
    // Collect last-active product info, FALET quantity, and notes.
    final result = await HandoverCreationDialog.show(
      context: context,
      productTypes: provider.productTypes,
      themeColor: line.color,
      currentProduct: provider.getSelectedProductType(line.number),
    );

    if (result == null || !context.mounted) return;

    // ── Step 2: Determine if FALET resolution is needed ──
    final bool operatorDeclaredFalet =
        result.lastActiveProductFaletQuantity != null &&
        result.lastActiveProductFaletQuantity! > 0 &&
        result.lastActiveProductTypeId != null;

    // Always fetch fresh FALET items when there might be open items,
    // or when the operator just declared a last-active product FALET.
    List<FaletItem> openItems = [];
    if (provider.hasOpenFalet(line.number) || operatorDeclaredFalet) {
      await provider.fetchFaletItems(line.number);
      if (!context.mounted) return;
      final faletResponse = provider.getFaletItems(line.number);
      openItems =
          faletResponse?.faletItems
              .where((item) => item.status == 'OPEN')
              .toList() ??
          [];
    }

    // ── Step 3: Auto carry-forward all open FALET items ──
    List<FaletResolutionEntry>? faletResolutions;

    // All open FALET items are automatically carried forward.
    // The last-active FALET (declared via lastActiveProductTypeId) is
    // implicitly CARRY_FORWARD on the backend — no resolution entry needed.
    if (openItems.isNotEmpty) {
      faletResolutions = openItems
          .map(
            (item) => FaletResolutionEntry(
              faletId: item.faletId,
              action: HandoverFaletAction.carryForward,
            ),
          )
          .toList();
    }

    // ── Step 4: Submit handover creation ──
    try {
      final handover = await provider.createLineHandover(
        line.number,
        lastActiveProductTypeId: result.lastActiveProductTypeId,
        lastActiveProductFaletQuantity: result.lastActiveProductFaletQuantity,
        notes: result.notes,
        faletResolutions: faletResolutions,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إنشاء طلب التسليم بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Show reconciliation summary if any items were reconciled
        if (handover != null && handover.reconciledFaletItems.isNotEmpty) {
          _showReconciliationSummary(context, handover);
        }
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        // Provide specific Arabic feedback for FALET-related errors
        final errorMessage = _mapFaletError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Maps FALET-specific error codes to actionable Arabic messages.
  /// Falls back to the default ApiException displayMessage.
  String _mapFaletError(ApiException e) {
    switch (e.code) {
      case 'HANDOVER_FALET_DECISION_REQUIRED':
      case 'HANDOVER_FALET_DECISION_MISSING':
        return 'يجب حل جميع عناصر الفالت المفتوحة. حاول مرة أخرى';
      case 'HANDOVER_FALET_NO_SESSION_PRODUCTION':
        return 'لا يوجد إنتاج نشط في هذه المناوبة لنوع المنتج. لا يمكن اعتبار الفالت محسوباً.';
      default:
        return e.displayMessage;
    }
  }

  void _showReconciliationSummary(
    BuildContext context,
    LineHandoverInfo handover,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ملخص ضم الفالت',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: handover.reconciledFaletItems.map((item) {
            final isSessionAccounted = item.isSessionAccounted;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isSessionAccounted
                        ? Icons.check_circle_outline_rounded
                        : Icons.merge_type_rounded,
                    size: 16,
                    color: isSessionAccounted
                        ? Colors.green.shade600
                        : line.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isSessionAccounted
                          ? '${item.productTypeName} (${item.reconciledQuantity}) — محسوب في إنتاج المناوبة'
                          : '${item.productTypeName} (${item.reconciledQuantity}) → ${item.scannedValue ?? ''}',
                      style: GoogleFonts.cairo(fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'حسناً',
              style: GoogleFonts.cairo(
                color: line.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleConfirmHandover(BuildContext context) async {
    final provider = context.read<PalletizingProvider>();
    final handover = provider.getPendingHandover(line.number);
    if (handover == null) return;

    // Show confirm dialog with optional receipt notes
    final receiptNotes = await HandoverConfirmDialog.show(context: context);

    // null means user cancelled
    if (receiptNotes == null || !context.mounted) return;

    try {
      await provider.confirmLineHandover(
        lineNumber: line.number,
        handoverId: handover.handoverId,
        receiptNotes: receiptNotes.isEmpty ? null : receiptNotes,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تأكيد التسليم بنجاح', style: GoogleFonts.cairo()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleRejectHandover(BuildContext context) async {
    final provider = context.read<PalletizingProvider>();

    // Refresh first so we open the dialog against the current snapshot IDs.
    // The strict-validation backend rejects observations carrying snapshot IDs
    // from a previous handover; cached state on this line could otherwise
    // produce HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH.
    await provider.refreshLineState(line.number);
    if (!context.mounted) return;

    final handover = provider.getPendingHandover(line.number);
    if (handover == null) return;

    final result = await HandoverRejectDialog.show(
      context: context,
      faletItems: handover.faletItems,
    );

    if (result == null || !context.mounted) return;

    try {
      await provider.rejectLineHandover(
        lineNumber: line.number,
        handoverId: handover.handoverId,
        incorrectQuantity: result.incorrectQuantity,
        otherReason: result.otherReason,
        otherReasonNotes: result.otherReasonNotes,
        itemObservations: result.itemObservations,
        undeclaredFaletFound: result.undeclaredFaletFound,
        undeclaredFaletObservedQuantity: result.undeclaredFaletObservedQuantity,
        undeclaredFaletNotes: result.undeclaredFaletNotes,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم رفض التسليم وسيتم مراجعته من قبل الإدارة',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on ApiException catch (e) {
      // Stale snapshot IDs: refresh the handover so the next attempt uses the
      // current set, and tell the user to retry.
      if (e.code == 'HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH' ||
          e.code == 'FALET_STATE_NOT_AVAILABLE_FOR_REJECTION') {
        await provider.refreshLineState(line.number);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Animated FALET button that blinks when there are unresolved open FALET items.
class _AnimatedFaletButton extends StatefulWidget {
  final ProductionLine line;
  final bool isMobile;
  final bool hasOpenFalet;
  final int openFaletCount;

  const _AnimatedFaletButton({
    required this.line,
    required this.isMobile,
    required this.hasOpenFalet,
    required this.openFaletCount,
  });

  @override
  State<_AnimatedFaletButton> createState() => _AnimatedFaletButtonState();
}

class _AnimatedFaletButtonState extends State<_AnimatedFaletButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blinkAnimation = Tween<double>(
      begin: 1.0,
      end: 0.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.hasOpenFalet) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedFaletButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasOpenFalet && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.hasOpenFalet && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.line.color;
    final hasOpen = widget.hasOpenFalet;

    final buttonPadding = EdgeInsets.symmetric(
      horizontal: widget.isMobile ? 14 : 18,
      vertical: widget.isMobile ? 12 : 16,
    );

    // No open FALET — static outlined button
    if (!hasOpen) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              FaletScreen.show(context: context, line: widget.line),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color, width: 1.5),
            padding: buttonPadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: Icon(
            Icons.inventory_2_outlined,
            size: widget.isMobile ? 18 : 20,
          ),
          label: Text(
            'فالت',
            style: GoogleFonts.cairo(
              fontSize: widget.isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Has open FALET — blinking elevated button with badge
    return AnimatedBuilder(
      animation: _blinkAnimation,
      builder: (context, _) {
        return SizedBox(
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: _blinkAnimation.value,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        FaletScreen.show(context: context, line: widget.line),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: buttonPadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: Icon(
                      Icons.warning_amber_rounded,
                      size: widget.isMobile ? 18 : 20,
                    ),
                    label: Text(
                      'فالت',
                      style: GoogleFonts.cairo(
                        fontSize: widget.isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              // Badge with count
              if (widget.openFaletCount > 0)
                Positioned(
                  top: -6,
                  left: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red.shade600, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.openFaletCount}',
                        style: GoogleFonts.cairo(
                          color: Colors.red.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
