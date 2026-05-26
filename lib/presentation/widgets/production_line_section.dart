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
import 'line_blocked_card.dart';
import 'line_context_strip.dart';
import 'overproduction_confirmation_dialog.dart';
import 'pallet_success_dialog.dart';
import 'palletizer_pin_screen.dart';
import 'falet_screen.dart';
import 'session_table_widget.dart';
import 'takeover_banner.dart';
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

        // Persistent takeover banner — a NON-blocking strip pinned to the top.
        // Placed before the full-screen overlays so those still cover it when
        // present; on an active line it is the only takeover UI on screen.
        // Renders nothing when there is no takeover (see TakeoverBanner).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TakeoverBanner(line: line),
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
              // V81+ (2026-05-21): when backend provides waiting-for-operator
              // Arabic copy, render verbatim; the provider getters return
              // `null` for absent / whitespace, which makes the card fall back
              // to its hardcoded Arabic strings.
              titleOverride: provider.getWaitingForOperatorTitle(line.number),
              bodyOverride:
                  provider.getWaitingForOperatorMessage(line.number),
            ),
          ),
        // Backend-authoritative `blocked` for a line that still has an
        // operator. Previously rendered no overlay, leaving the worker with a
        // silently disabled "Create Pallet" button and no explanation —
        // exactly the gap where downstream error snackbars from create /
        // FALET calls were taking over and surfacing misleading credentials
        // text. The card maps known blockedReason values to Arabic copy.
        if (uiState == LineUiState.blocked)
          Positioned.fill(child: LineBlockedCard(line: line)),
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
    // isPalletCreationBlocked folds in the existing line blocks plus the
    // takeover-specific blocks (backend `blocked`, auto-released line).
    final isBlocked = provider.isPalletCreationBlocked(line.number);
    final isCreating = provider.isLineCreating(line.number);

    // V81 plan enforcement — the backend rejects pallet creation without a
    // current plan item, so the button stays disabled until one exists.
    // Either `productionPlanBlocked` is set, or the line is missing the plan
    // product id altogether (older responses / edge cases).
    final planBlocked = provider.isProductionPlanBlocked(line.number);
    final missingPlanProduct =
        provider.getCurrentPlanItemProductTypeId(line.number) == null;
    final planMessage =
        provider.getProductionPlanBlockedMessage(line.number) ??
            'لا يوجد بند إنتاج نشط لهذا الخط. '
                'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.';
    final blockedByPlan = planBlocked || missingPlanProduct;

    // When the block is caused by a takeover, surface the reason — otherwise a
    // disabled button with no explanation reads as a bug.
    final takeover = provider.getTakeover(line.number);
    final blockedByTakeover = isBlocked && takeover != null;

    final button = ElevatedButton(
      onPressed: (isCreating || isBlocked || blockedByPlan)
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

    // Pick the explanation that matches the reason create is disabled.
    // Plan-blocked is the more specific reason and should win when both apply.
    String? footerMessage;
    if (blockedByPlan) {
      footerMessage = planMessage;
    } else if (blockedByTakeover) {
      footerMessage = 'لا يمكن إنشاء طبليات الآن — الخط في وضع تسليم. '
          'الرجاء الانتظار حتى يكمل المشغّل استلام الخط.';
    }

    if (footerMessage == null) return button;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 8),
        Text(
          footerMessage,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.cairo(
            fontSize: 12.5,
            height: 1.5,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final provider = context.read<PalletizingProvider>();

    // Pre-flight V81 plan gate. The button is disabled when the plan is
    // blocked or there is no plan product, but a stale frame could still
    // trigger this path — surface the backend message and stop.
    if (provider.isProductionPlanBlocked(line.number) ||
        provider.getCurrentPlanItemProductTypeId(line.number) == null) {
      _showInfoSnack(
        context,
        provider.getProductionPlanBlockedMessage(line.number) ??
            'لا يوجد بند إنتاج نشط لهذا الخط. '
                'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
      );
      return;
    }

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
      // V81: defense-in-depth. The plan-required write-path 409 maps to the
      // same Arabic message + a line-state refresh that re-routes the UI.
      if (e.code == 'PRODUCTION_PLAN_ITEM_REQUIRED') {
        await provider.refreshLineState(line.number);
        if (!context.mounted) return;
        _showInfoSnack(context, e.displayMessage);
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

    // Step 2 — soft block: no active production-plan item on the line. The
    // plan is managed centrally; we just surface the backend-localized hint
    // verbatim (V81 backend returns the canonical Arabic message) and stop.
    if (ctx.blockReason == 'NO_ACTIVE_PLAN_ITEM') {
      _showInfoSnack(
        context,
        (ctx.messageAr?.isNotEmpty ?? false)
            ? ctx.messageAr!
            : 'لا يوجد بند إنتاج نشط لهذا الخط. '
                'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
      );
      return;
    }

    // Step 3 — mandatory first-pallet FALET-consumption confirmation when the
    // backend says matching FALET is open for this product. The dialog itself
    // IS the confirmation step — on confirm we submit a full-target-quantity
    // pallet directly. There is no second CreatePalletDialog, and the FALET
    // bypass is forbidden (cancel aborts).
    if (ctx.canSuggestFirstPalletDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FirstPalletSuggestionDialog(line: line, context: ctx),
      );
      if (!context.mounted) return;
      if (confirmed != true) return; // cancelled / dismissed → abort

      // Safety re-check: a plan item may have been closed between the button
      // press and the operator's confirm tap. Refresh, then validate.
      await provider.refreshLineState(line.number);
      if (!context.mounted) return;

      final firstPalletProductId =
          provider.getCurrentPlanItemProductTypeId(line.number);
      if (firstPalletProductId == null ||
          provider.isProductionPlanBlocked(line.number)) {
        _showInfoSnack(
          context,
          provider.getProductionPlanBlockedMessage(line.number) ??
              'لا يوجد بند إنتاج نشط لهذا الخط. '
                  'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
        );
        return;
      }

      // Submit the FIRST pallet with the full target quantity. The backend
      // attributes the matching FALET to this pallet automatically; the
      // request payload is the total pallet target, NOT the FALET count.
      // currentPlanItemPackagesPerPallet is the canonical target — fall back
      // to the provider's plan default only if the context was missing it.
      final totalQuantity = ctx.currentPlanItemPackagesPerPallet ??
          provider.getCurrentPlanItemPackagesPerPallet(line.number) ??
          0;
      if (totalQuantity <= 0) {
        _showErrorSnack(context, 'تعذّر تحديد حجم الطبلية الهدف');
        return;
      }

      await _submitCreatePallet(
        context,
        productTypeId: firstPalletProductId,
        quantity: totalQuantity,
      );
      return;
    }

    // Step 4 — normal pallet creation path (no matching FALET to consume).
    // Refresh line state once so the production-plan defaults reflect a
    // recently-changed plan item before opening the dialog.
    await provider.refreshLineState(line.number);
    if (!context.mounted) return;

    // Re-check the plan gate after the refresh — admin may have closed the
    // item between the button press and this point.
    final planProductId =
        provider.getCurrentPlanItemProductTypeId(line.number);
    if (planProductId == null ||
        provider.isProductionPlanBlocked(line.number)) {
      _showInfoSnack(
        context,
        provider.getProductionPlanBlockedMessage(line.number) ??
            'لا يوجد بند إنتاج نشط لهذا الخط. '
                'يرجى مراجعة الإدارة لإضافة بند إلى خطة الإنتاج.',
      );
      return;
    }

    // The product cache is derived purely from the current plan item (see
    // PalletizingProvider._resolveProductType). Use it as the read-only
    // product to display in the dialog.
    final ProductType? planProduct =
        provider.getCurrentPlanItemProductType(line.number);

    final planDefault =
        provider.getCurrentPlanItemPackagesPerPallet(line.number);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreatePalletDialog(
        line: line,
        initialProductType: planProduct,
        initialQuantity: planDefault,
        nonMatchingFaletQuantity: ctx.nonMatchingFaletQuantity,
      ),
    );

    if (result == null || !context.mounted) return;

    // Dialog returns only `quantity` by construction — there is no product
    // picker. The request product is the current plan item id.
    final quantity = result['quantity'] as int;

    await _submitCreatePallet(
      context,
      productTypeId: planProductId,
      quantity: quantity,
    );
  }

  /// Submits the create-pallet request with optional overproduction confirm.
  /// On `PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED`, opens the
  /// confirmation dialog and, on confirm, re-submits the IDENTICAL payload
  /// with `confirmOverproduction: true`. On
  /// `PRODUCTION_PLAN_PRODUCT_MISMATCH` the line state was already refreshed
  /// inside the provider — surface the Arabic message and stop.
  Future<void> _submitCreatePallet(
    BuildContext context, {
    required int productTypeId,
    required int quantity,
    bool confirmOverproduction = false,
  }) async {
    final provider = context.read<PalletizingProvider>();
    try {
      final palletResponse = await provider.createPallet(
        lineNumber: line.number,
        productTypeId: productTypeId,
        quantity: quantity,
        confirmOverproduction: confirmOverproduction,
      );
      if (context.mounted) {
        _showSuccessDialog(context, palletResponse);
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED' &&
          !confirmOverproduction) {
        final confirmed = await OverproductionConfirmationDialog.show(
          context,
          message: e.displayMessage,
        );
        if (!context.mounted) return;
        if (!confirmed) return; // operator cancelled — abort
        await _submitCreatePallet(
          context,
          productTypeId: productTypeId,
          quantity: quantity,
          confirmOverproduction: true,
        );
        return;
      }
      // PRODUCTION_PLAN_PRODUCT_MISMATCH: the provider already refreshed line
      // state, so the screen will re-render with the new plan product. Show
      // only the Arabic message — never the raw English backend text.
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
