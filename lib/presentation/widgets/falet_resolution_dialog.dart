import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/falet_item.dart';
import '../../domain/entities/falet_resolution_entry.dart';
import '../../domain/entities/handover_falet_action.dart';
import '../../domain/entities/pending_last_active_falet.dart';

class FaletResolutionDialog extends StatefulWidget {
  final List<FaletItem> openFaletItems;
  final Color themeColor;

  /// Optional: the last-active-product FALET the operator just declared.
  /// When non-null, affects how items are displayed (merged qty, labels).
  final PendingLastActiveFalet? pendingLastActiveFalet;

  const FaletResolutionDialog({
    super.key,
    required this.openFaletItems,
    required this.themeColor,
    this.pendingLastActiveFalet,
  });

  static Future<List<FaletResolutionEntry>?> show({
    required BuildContext context,
    required List<FaletItem> openFaletItems,
    required Color themeColor,
    PendingLastActiveFalet? pendingLastActiveFalet,
  }) {
    return showDialog<List<FaletResolutionEntry>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FaletResolutionDialog(
        openFaletItems: openFaletItems,
        themeColor: themeColor,
        pendingLastActiveFalet: pendingLastActiveFalet,
      ),
    );
  }

  @override
  State<FaletResolutionDialog> createState() => _FaletResolutionDialogState();
}

class _FaletResolutionDialogState extends State<FaletResolutionDialog> {
  // Per-FALET item state: action chosen
  late final Map<int, HandoverFaletAction> _actions;

  /// The faletId that the last-active-product FALET will merge into (if any).
  int? get _mergeTargetFaletId =>
      widget.pendingLastActiveFalet?.mergesWithFaletId;

  /// Whether the pending last-active FALET is brand-new (no merge target).
  bool get _hasVirtualLastActiveFalet =>
      widget.pendingLastActiveFalet != null &&
      !widget.pendingLastActiveFalet!.willMerge;

  @override
  void initState() {
    super.initState();
    _actions = {};
    // Default all items to CARRY_FORWARD
    for (final item in widget.openFaletItems) {
      _actions[item.faletId] = HandoverFaletAction.carryForward;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 520.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            color: widget.themeColor,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'حل عناصر الفالت المفتوحة',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: widget.themeColor,
                fontSize: isMobile ? 15 : 17,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 16, 
        isMobile ? 12 : 16, 
        isMobile ? 12 : 16, 
        isMobile ? 6 : 8
      ),
      content: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.amber.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يجب تحديد إجراء لكل عنصر فالت مفتوح قبل إتمام التسليم',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 12 : 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // FALET items list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount:
                    widget.openFaletItems.length +
                    (_hasVirtualLastActiveFalet ? 1 : 0),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  // Virtual last-active card at the end
                  if (index == widget.openFaletItems.length &&
                      _hasVirtualLastActiveFalet) {
                    return _buildVirtualLastActiveFaletCard(isMobile);
                  }
                  return _buildFaletItemCard(
                    widget.openFaletItems[index],
                    isMobile,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: _buildActions(isMobile),
    );
  }

  Widget _buildFaletItemCard(FaletItem item, bool isMobile) {
    final action = _actions[item.faletId]!;
    final isAccounted =
        action == HandoverFaletAction.alreadyAccountedInSession;
    final fontSize = isMobile ? 13.0 : 14.0;

    // Check if this FALET item is the merge target for the last-active FALET
    final isMergeTarget = _mergeTargetFaletId == item.faletId;
    final pendingFalet = widget.pendingLastActiveFalet;
    // Display combined quantity if this item will absorb last-active quantity
    final displayQuantity = isMergeTarget && pendingFalet != null
        ? item.quantity + pendingFalet.quantity
        : item.quantity;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccounted
              ? widget.themeColor.withValues(alpha: 0.4)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: product type + quantity + source label
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: isAccounted
                  ? widget.themeColor.withValues(alpha: 0.1)
                  : widget.themeColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: widget.themeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.productTypeName,
                        style: GoogleFonts.cairo(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: widget.themeColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'كمية: $displayQuantity',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Source label
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'فالت مفتوح على الخط',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 10 : 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isMergeTarget && pendingFalet != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+ ${pendingFalet.quantity} من المنتج النشط',
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 10 : 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action selection
          Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Carry Forward option
                _buildActionRadio(
                  item: item,
                  value: HandoverFaletAction.carryForward,
                  label: 'ترحيل للمناوبة القادمة',
                  icon: Icons.arrow_forward_rounded,
                  isMobile: isMobile,
                ),

                // Accounted in Session option
                _buildActionRadio(
                  item: item,
                  value: HandoverFaletAction.alreadyAccountedInSession,
                  label: 'محسوب في إنتاج المناوبة',
                  icon: Icons.check_circle_outline_rounded,
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRadio({
    required FaletItem item,
    required HandoverFaletAction value,
    required String label,
    required IconData icon,
    required bool isMobile,
  }) {
    final isSelected = _actions[item.faletId] == value;

    return InkWell(
      onTap: () {
        setState(() {
          _actions[item.faletId] = value;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Radio<HandoverFaletAction>(
              value: value,
              groupValue: _actions[item.faletId],
              onChanged: (v) {
                setState(() {
                  _actions[item.faletId] = v!;
                });
              },
              activeColor: widget.themeColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              icon,
              size: 18,
              color: isSelected ? widget.themeColor : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 13 : 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card for the last-active-product FALET that is brand-new (no merge
  /// target). The backend will auto-carry-forward this FALET. The card is
  /// informational only — no resolution entry is returned for it.
  Widget _buildVirtualLastActiveFaletCard(bool isMobile) {
    final pendingFalet = widget.pendingLastActiveFalet!;
    final fontSize = isMobile ? 13.0 : 14.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: Colors.green.shade100.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.green.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pendingFalet.productTypeName,
                        style: GoogleFonts.cairo(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'كمية: ${pendingFalet.quantity}',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'فالت المنتج النشط (جديد)',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 10 : 11,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Auto carry-forward notice
          Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم ترحيله تلقائياً للمناوبة القادمة',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canSubmit() {
    for (final item in widget.openFaletItems) {
      if (_actions[item.faletId] == null) return false;
    }
    return true;
  }

  List<Widget> _buildActions(bool isMobile) {
    return [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _canSubmit() ? _handleSubmit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.themeColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.themeColor.withValues(alpha: 0.4),
            padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'تأكيد',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 15 : 16,
            ),
          ),
        ),
      ),
    ];
  }

  void _handleSubmit() {
    final resolutions = <FaletResolutionEntry>[];
    for (final item in widget.openFaletItems) {
      resolutions.add(
        FaletResolutionEntry(
          faletId: item.faletId,
          action: _actions[item.faletId]!,
        ),
      );
    }
    Navigator.of(context).pop(resolutions);
  }
}
