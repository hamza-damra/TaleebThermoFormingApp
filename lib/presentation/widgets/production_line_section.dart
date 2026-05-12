import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/first_pallet_context.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart' as entity;
import '../providers/palletizing_provider.dart';
import 'create_pallet_dialog.dart';
import 'first_pallet_suggestion_dialog.dart';
import 'legacy_handover_info_card.dart';
import 'line_context_strip.dart';
import 'pallet_success_dialog.dart';
import 'palletizer_pin_screen.dart';
import 'falet_screen.dart';
import 'session_table_widget.dart';
import 'thermoforming_waiting_card.dart';

class ProductionLineSection extends StatelessWidget {
  final ProductionLine line;
  final entity.ProductionLine? productionLineEntity;

  /// Callback fired when the user taps "تغيير الخط" in the blocking overlay.
  /// The parent (PalletizingScreen) wires this to the TabController.
  final VoidCallback? onSwitchLine;

  /// Whether another line tab exists that the worker could switch to.
  final bool canSwitchLine;

  const ProductionLineSection({
    super.key,
    required this.line,
    this.productionLineEntity,
    this.onSwitchLine,
    this.canSwitchLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final horizontalPadding = isMobile ? 16.0 : 24.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final uiState = provider.getUiState(line.number);

    // Use a neutral background when the line is in a blocked / waiting state
    // so the screen never looks like an active production line.
    final isInactiveState =
        uiState == LineUiState.waitingForThermoforming ||
        uiState == LineUiState.blocked;
    final bgColor = isInactiveState ? const Color(0xFFF5F5F5) : line.lightColor;

    // "تغيير الخط" is only available when another line is usable AND the
    // parent wired a callback for it.
    final bool showSwitchLine = canSwitchLine && onSwitchLine != null;

    return Stack(
      children: [
        Container(
          color: bgColor,
          child: SafeArea(
            top: false,
            child: Column(
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
                          _buildTopActionButtons(context, provider, isMobile),
                          _buildFormCard(context),
                          SizedBox(height: isMobile ? 20 : 28),
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

        // Per-line state overlays. Order matters: blocked / legacy-handover
        // pending always wins so a real failure never gets masked as
        // "waiting for the operator". Positioned.fill is REQUIRED — without
        // it, non-positioned Stack children may not size to cover the base
        // Container and the user can see / interact with the screen behind.
        if (uiState == LineUiState.pendingHandoverIncoming ||
            uiState == LineUiState.pendingHandoverReview)
          Positioned.fill(child: LegacyHandoverInfoCard(line: line)),
        if (uiState == LineUiState.waitingForThermoforming)
          Positioned.fill(
            child: ThermoformingWaitingCard(
              line: line,
              canSwitchLine: showSwitchLine,
              onSwitchLine: onSwitchLine,
            ),
          ),
        if (uiState == LineUiState.needsPalletizerAuth)
          Positioned.fill(child: PalletizerPinScreen(line: line)),
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

    if (!showOpenItems) return const SizedBox.shrink();

    // Hide the FALET button entirely when no FALET is open for this line —
    // an empty outlined button reads as a dead UI element on the palletizing
    // screen, and reserves vertical space that the section above can use.
    final hasOpenFalet = provider.hasOpenFalet(line.number);
    if (!hasOpenFalet) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      child: _AnimatedFaletButton(
        line: line,
        isMobile: isMobile,
        hasOpenFalet: hasOpenFalet,
        openFaletCount: provider.getOpenFaletCount(line.number),
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

    // Step 1 — call the new first-pallet-context endpoint. The backend tells
    // us whether to open the include-FALET suggestion dialog and surfaces
    // soft blocks (no current product, etc.) without throwing.
    FirstPalletContext ctx;
    try {
      ctx = await provider.fetchFirstPalletContext(line.number);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // 409 LINE_BLOCKED_BY_PENDING_HANDOVER → state refresh routes the UI to
      // the LegacyHandoverInfoCard overlay; no extra snackbar needed.
      if (e.code == 'LINE_BLOCKED_BY_PENDING_HANDOVER') {
        await provider.refreshLineState(line.number);
        return;
      }
      _showErrorSnack(context, e.displayMessage);
      return;
    } catch (_) {
      if (!context.mounted) return;
      _showErrorSnack(context, 'فشل في تحميل سياق أول طبلية');
      return;
    }

    if (!context.mounted) return;

    // Step 2 — soft block: no current product set on the line. The product is
    // managed by the Thermoforming/Roll Worker apps; we just surface the
    // backend-localized hint and stop.
    if (ctx.blockReason == 'CURRENT_PRODUCT_REQUIRED') {
      _showInfoSnack(
        context,
        (ctx.messageAr?.isNotEmpty ?? false)
            ? ctx.messageAr!
            : 'اختر المنتج الحالي على الخط قبل إنشاء طبلية',
      );
      return;
    }

    // Step 3 — optional first-pallet suggestion when matching FALET is open.
    int? prefilledQuantity;
    if (ctx.canSuggestFirstPalletDialog) {
      final choice = await showDialog<FirstPalletDialogResult>(
        context: context,
        builder: (_) => FirstPalletSuggestionDialog(line: line, context: ctx),
      );
      if (!context.mounted) return;
      if (choice == null) return; // user dismissed → abort, no pallet created
      if (choice == FirstPalletDialogResult.useFalet) {
        prefilledQuantity = ctx.suggestedFaletQuantityForFirstPallet;
      }
    }

    // Step 4 — resolve the product to pre-select. Prefer the productType
    // returned by the context (server-authoritative); fall back to whatever
    // the line cache already had.
    ProductType? initialProductType = provider.getSelectedProductType(
      line.number,
    );
    final ctxProductId = ctx.currentProductTypeId;
    if (ctxProductId != null) {
      final match = provider.productTypes
          .where((p) => p.id == ctxProductId)
          .firstOrNull;
      if (match != null) initialProductType = match;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreatePalletDialog(
        line: line,
        initialProductType: initialProductType,
        initialQuantity: prefilledQuantity,
        nonMatchingFaletQuantity: ctx.nonMatchingFaletQuantity,
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
      _showErrorSnack(context, e.displayMessage);
    } catch (e) {
      if (context.mounted) {
        _showErrorSnack(context, 'فشل في إنشاء الطبلية');
      }
    }
  }

  void _showErrorSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(),
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showInfoSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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
