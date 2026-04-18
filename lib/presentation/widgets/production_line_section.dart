import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/falet_resolution_entry.dart';
import '../../domain/entities/handover_falet_action.dart';
import '../../domain/entities/first_pallet_suggestion.dart';
import '../../domain/entities/line_handover_info.dart';
// pending_last_active_falet.dart removed — no longer needed after resolution dialog removal
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart' as entity;
import '../providers/palletizing_provider.dart';
import 'create_pallet_dialog.dart';
import 'handover_creation_dialog.dart';
import 'handover_confirm_dialog.dart';
import 'handover_reject_dialog.dart';
import 'line_auth_overlay.dart';
import 'line_handover_card.dart';
import 'pallet_success_dialog.dart';
import 'product_switch_dialog.dart';
import 'product_type_image.dart';
import 'searchable_picker_dialog.dart';

import 'mandatory_falet_pallet_dialog.dart';
// falet_resolution_dialog.dart removed — FALET items auto carry-forward
import 'falet_screen.dart';
import 'session_table_widget.dart';

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
    // Use lineUiMode as the single source of truth for which UI to render
    final lineUiMode = provider.getLineUiMode(line.number);
    final showPinOverlay =
        lineUiMode == 'NEEDS_AUTHORIZATION' ||
        (lineUiMode == null && !provider.isLineAuthorized(line.number));
    final showPendingHandoverIncoming =
        lineUiMode == 'PENDING_HANDOVER_NEEDS_INCOMING';

    final isHandoverReview = lineUiMode == 'PENDING_HANDOVER_REVIEW';

    return Stack(
      children: [
        // Main content
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
                      // Scrollable content area
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
                                // Top action buttons row (فالت + تسليم مناوبة)
                                _buildTopActionButtons(
                                  context,
                                  provider,
                                  isMobile,
                                ),
                                _buildFormCard(context),
                                SizedBox(height: isMobile ? 20 : 28),
                                // Pending handover card (from backend state)
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
                                // Session table (replaces old summary card)
                                _buildSessionTable(context),
                                SizedBox(height: isMobile ? 24 : 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Fixed bottom button
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

        // Per-line auth overlay — controlled by backend-driven lineUiMode only
        if (showPinOverlay) LineAuthOverlay(line: line),

        // Pending handover needs incoming operator — show PIN overlay for incoming
        if (showPendingHandoverIncoming && !showPinOverlay)
          LineAuthOverlay(line: line),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAuthorizedOperatorCard(context),
            SizedBox(height: isMobile ? 20 : 28),
            _buildProductField(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorizedOperatorCard(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final operator = provider.getAuthorizedOperator(line.number);
    final authState = provider.getLineAuth(line.number);
    final isAuthorized = provider.isLineAuthorized(line.number);
    // When authorized but operator object may be null, show "مشغل مفوض" rather than "لا يوجد"
    final hasActiveOperator = isAuthorized || operator != null;

    return _buildFieldContainer(
      context: context,
      label: 'المشغل المسؤول',
      icon: Icons.person_outline_rounded,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 20,
          vertical: isMobile ? 14 : 18,
        ),
        decoration: BoxDecoration(
          color: hasActiveOperator
              ? line.color.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          border: Border.all(
            color: hasActiveOperator
                ? line.color.withValues(alpha: 0.3)
                : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: isMobile ? 10 : 12,
              height: isMobile ? 10 : 12,
              decoration: BoxDecoration(
                color: hasActiveOperator
                    ? Colors.green.shade400
                    : Colors.grey.shade400,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: isMobile ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operator?.displayLabel ??
                        (isAuthorized ? 'مشغل مفوض' : 'لا يوجد مشغل مفوض'),
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 15 : 17,
                      fontWeight: FontWeight.w600,
                      color: hasActiveOperator
                          ? Colors.black87
                          : Colors.grey.shade400,
                    ),
                  ),
                  if (hasActiveOperator && authState?.authorizedAt != null)
                    Text(
                      'تم التفويض',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 12 : 13,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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

  Widget _buildProductField(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final selectedProductType = provider.getSelectedProductType(line.number);

    if (provider.productTypes.isEmpty) {
      return _buildFieldContainer(
        context: context,
        label: 'نوع المنتج',
        icon: Icons.inventory_2_outlined,
        child: _buildWarningBox(
          context,
          'لا يوجد أنواع منتجات - يرجى إضافتها من لوحة الإدارة',
        ),
      );
    }

    return _buildFieldContainer(
      context: context,
      label: 'نوع المنتج',
      icon: Icons.inventory_2_outlined,
      child: InkWell(
        onTap: () async {
          final selected = await SearchablePickerDialog.show<ProductType>(
            context: context,
            title: 'اختر نوع المنتج',
            searchHint: 'ابحث عن المنتج...',
            items: provider.productTypes,
            selectedItem: selectedProductType,
            displayTextExtractor: (pt) => pt.productName,
            subtitleExtractor: (pt) => pt.description ?? '',
            searchMatcher: (pt, query) {
              final queryLower = query.toLowerCase();
              return pt.name.toLowerCase().contains(queryLower) ||
                  pt.productName.toLowerCase().contains(queryLower) ||
                  pt.color.toLowerCase().contains(queryLower) ||
                  pt.prefix.toLowerCase().contains(queryLower) ||
                  pt.displayLabel.toLowerCase().contains(queryLower);
            },
            themeColor: line.color,
          );
          if (selected != null && context.mounted) {
            await _handleProductSelection(context, selected);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 20,
            vertical: isMobile ? 18 : 22,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedProductType?.productName ?? 'اختر نوع المنتج',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 15 : 17,
                        fontWeight: FontWeight.w500,
                        color: selectedProductType != null
                            ? Colors.black87
                            : Colors.grey.shade400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (selectedProductType?.description != null &&
                        selectedProductType!.description!.trim().isNotEmpty)
                      Text(
                        selectedProductType.description!,
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 14,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: line.color,
                size: isMobile ? 24 : 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles product selection with product-switch loose-balance flow
  Future<void> _handleProductSelection(
    BuildContext context,
    ProductType newProduct,
  ) async {
    final provider = context.read<PalletizingProvider>();
    final currentProduct = provider.getSelectedProductType(line.number);

    // Same product — nothing to do
    if (currentProduct != null && currentProduct.id == newProduct.id) {
      return;
    }

    // First-time selection (no product set on line) — confirm then POST /select-product
    if (currentProduct == null) {
      final confirmed = await _showProductTypeConfirmationDialog(
        context,
        newProduct,
      );
      if (confirmed == true && context.mounted) {
        final success = await provider.selectProductOnLine(
          lineNumber: line.number,
          productTypeId: newProduct.id,
        );
        if (!success && context.mounted) {
          final error = provider.getLineError(line.number);
          if (error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error, style: GoogleFonts.cairo()),
                backgroundColor: Colors.red,
              ),
            );
            provider.clearLineError(line.number);
          }
        }
      }
      return;
    }

    // Different product → product-switch dialog (loose balance flow)
    if (!context.mounted) return;
    final looseCount = await ProductSwitchDialog.show(
      context: context,
      previousProduct: currentProduct,
      newProduct: newProduct,
      themeColor: line.color,
    );

    if (looseCount == null || !context.mounted) return; // Cancelled

    // Submit product switch to backend (provider hydrates state from response)
    final success = await provider.switchProduct(
      lineNumber: line.number,
      previousProductTypeId: currentProduct.id,
      newProductTypeId: newProduct.id,
      looseCount: looseCount,
    );

    if (!success && context.mounted) {
      final error = provider.getLineError(line.number);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'فشل في تبديل المنتج',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      provider.clearLineError(line.number);
    }
  }

  Widget _buildFieldContainer({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: line.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: line.color, size: isMobile ? 18 : 22),
            ),
            SizedBox(width: isMobile ? 10 : 12),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 12 : 14),
        child,
      ],
    );
  }

  Widget _buildWarningBox(BuildContext context, String message) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber.shade700,
            size: isMobile ? 22 : 26,
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 13 : 15,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showProductTypeConfirmationDialog(
    BuildContext context,
    ProductType productType,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);

    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight * 0.85;

    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isMobile ? 340 : 420,
            maxHeight: maxDialogHeight,
          ),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 14 : 18),
                        decoration: BoxDecoration(
                          color: line.color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.help_outline_rounded,
                          color: line.color,
                          size: isMobile ? 36 : 44,
                        ),
                      ),
                      SizedBox(height: isMobile ? 16 : 20),
                      Text(
                        'تأكيد نوع المنتج',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 20 : 24,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8 : 12),
                      Text(
                        'هل أنت متأكد من اختيار هذا المنتج؟',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 14 : 16,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isMobile ? 20 : 28),
                      _buildFullWidthProductImage(productType, isMobile),
                      SizedBox(height: isMobile ? 16 : 20),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isMobile ? 16 : 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              line.color.withValues(alpha: 0.08),
                              line.color.withValues(alpha: 0.04),
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: line.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              productType.compactLabel,
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: line.color,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (productType.description != null &&
                                productType.description!.trim().isNotEmpty) ...[
                              SizedBox(height: isMobile ? 4 : 6),
                              Text(
                                productType.description!,
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 13 : 15,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 24 : 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'لا',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isMobile ? 12 : 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: line.color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'نعم',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullWidthProductImage(ProductType productType, bool isMobile) {
    if (productType.imageUrl == null || productType.imageUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: isMobile ? 160 : 180,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ProductTypeImage(
          imageUrl: productType.imageUrl,
          size: isMobile ? 160 : 180,
          borderRadius: 16,
          showBorder: false,
          fit: BoxFit.contain,
        ),
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

    // ── Proactive check: eligible mandatory FALET for current product? ──
    final suggestion = await provider.fetchFirstPalletSuggestion(line.number);
    if (!context.mounted) return;

    if (suggestion != null && suggestion.available) {
      // Show guided first-pallet dialog directly inside the create flow
      await _handleMandatoryFaletConversion(context, provider, suggestion);
      return;
    }

    // ── Fallback: suggestion endpoint failed but open FALET may still exist ──
    // Check GET /falet items for current product match
    final faletFallback = await _findMatchingFaletItem(provider);
    if (!context.mounted) return;
    if (faletFallback != null) {
      await _handleMandatoryFaletConversionFromItem(
        context, provider, faletFallback,
      );
      return;
    }

    // ── Normal pallet creation (no eligible FALET) ──
    final initialProductType = provider.getSelectedProductType(line.number);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreatePalletDialog(
        line: line,
        initialProductType: initialProductType,
      ),
    );

    if (result != null && context.mounted) {
      final productType = result['productType'] as ProductType;
      final quantity = result['quantity'] as int;

      try {
        final palletResponse = await context
            .read<PalletizingProvider>()
            .createPallet(
              lineNumber: line.number,
              productTypeId: productType.id,
              quantity: quantity,
            );

        if (context.mounted) {
          _showSuccessDialog(context, palletResponse);
        }
      } on ApiException catch (e) {
        if (context.mounted) {
          // ── 409 fallback: FALET appeared between proactive check and creation ──
          if (e.code == 'FALET_MUST_BE_CONSUMED_FIRST') {
            await _handleFaletMustBeConsumedFallback(context, provider);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.displayMessage, style: GoogleFonts.cairo()),
                backgroundColor: Colors.red,
              ),
            );
          }
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
  }

  /// Primary path: eligible mandatory FALET detected proactively.
  /// Shows the purpose-built MandatoryFaletPalletDialog directly inside the
  /// create-pallet flow — guided completion, not a generic conversion tool.
  Future<void> _handleMandatoryFaletConversion(
    BuildContext context,
    PalletizingProvider provider,
    FirstPalletSuggestion suggestion,
  ) async {
    final freshQty = await MandatoryFaletPalletDialog.show(
      context: context,
      suggestion: suggestion,
      themeColor: line.color,
    );

    if (freshQty != null && context.mounted) {
      try {
        final response = await provider.convertFaletToPallet(
          lineNumber: line.number,
          faletId: suggestion.faletId!,
          additionalFreshQuantity: freshQty,
        );

        if (response != null && context.mounted) {
          provider.clearFirstPalletSuggestion(line.number);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PalletSuccessDialog(
              pallet: response.pallet,
              lineColor: line.color,
              lineNumber: line.number,
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
  }

  /// Fallback: 409 FALET_MUST_BE_CONSUMED_FIRST hit during normal createPallet.
  /// Re-fetches suggestion and offers inline FALET conversion as recovery.
  /// If suggestion endpoint also fails, falls back to GET /falet items.
  Future<void> _handleFaletMustBeConsumedFallback(
    BuildContext context,
    PalletizingProvider provider,
  ) async {
    // Try suggestion endpoint first
    final suggestion = await provider.fetchFirstPalletSuggestion(line.number);
    if (!context.mounted) return;

    if (suggestion != null && suggestion.available) {
      await _handleMandatoryFaletConversion(context, provider, suggestion);
      return;
    }

    // Suggestion endpoint failed — try FALET items fallback
    final faletItem = await _findMatchingFaletItem(provider);
    if (!context.mounted) return;

    if (faletItem != null) {
      await _handleMandatoryFaletConversionFromItem(
        context, provider, faletItem,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'يوجد فالت مفتوح لهذا المنتج يجب استهلاكه أولاً',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Find an OPEN FALET item matching the current product on this line.
  /// Uses GET /falet data (fetches if needed). Returns null if no match.
  Future<FaletItem?> _findMatchingFaletItem(
    PalletizingProvider provider,
  ) async {
    await provider.fetchFaletItems(line.number);
    final faletResponse = provider.getFaletItems(line.number);
    if (faletResponse == null || faletResponse.isEmpty) return null;

    final currentProduct = provider.getSelectedProductType(line.number);
    if (currentProduct == null) return null;

    // Find first OPEN item matching current product
    return faletResponse.faletItems
        .where(
          (item) =>
              item.status == 'OPEN' &&
              item.productTypeId == currentProduct.id &&
              !item.managerResolved,
        )
        .firstOrNull;
  }

  /// Fallback conversion path using a raw FaletItem (when suggestion endpoint
  /// is unavailable). Uses MandatoryFaletPalletDialog.showFromFaletItem.
  Future<void> _handleMandatoryFaletConversionFromItem(
    BuildContext context,
    PalletizingProvider provider,
    FaletItem item,
  ) async {
    // Look up pallet capacity from product type reference
    final productType = provider.productTypes
        .where((p) => p.id == item.productTypeId)
        .firstOrNull;
    final palletCapacity = productType?.packageQuantity;

    final freshQty = await MandatoryFaletPalletDialog.showFromFaletItem(
      context: context,
      item: item,
      themeColor: line.color,
      fullPalletCapacity: palletCapacity,
    );

    if (freshQty != null && context.mounted) {
      try {
        final response = await provider.convertFaletToPallet(
          lineNumber: line.number,
          faletId: item.faletId,
          additionalFreshQuantity: freshQty,
        );

        if (response != null && context.mounted) {
          provider.clearFirstPalletSuggestion(line.number);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => PalletSuccessDialog(
              pallet: response.pallet,
              lineColor: line.color,
              lineNumber: line.number,
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
          .map((item) => FaletResolutionEntry(
                faletId: item.faletId,
                action: HandoverFaletAction.carryForward,
              ))
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
    final handover = provider.getPendingHandover(line.number);
    if (handover == null) return;

    // Show structured rejection dialog
    final result = await HandoverRejectDialog.show(
      context: context,
      faletItems: handover.faletItems,
    );

    // null means user cancelled
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
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
          icon: Icon(Icons.inventory_2_outlined,
              size: widget.isMobile ? 18 : 20),
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
                    icon: Icon(Icons.warning_amber_rounded,
                        size: widget.isMobile ? 18 : 20),
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
                      border: Border.all(
                          color: Colors.red.shade600, width: 2),
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
