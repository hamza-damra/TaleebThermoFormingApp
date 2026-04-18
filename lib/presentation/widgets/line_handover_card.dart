import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/line_handover_info.dart';
import '../../domain/entities/product_type.dart';

class LineHandoverCard extends StatelessWidget {
  final ProductionLine line;
  final LineHandoverInfo handover;
  final VoidCallback? onResolve;
  final VoidCallback? onReject;
  final bool isResolving;
  final bool showResolveActions;

  const LineHandoverCard({
    super.key,
    required this.line,
    required this.handover,
    this.onResolve,
    this.onReject,
    this.isResolving = false,
    this.showResolveActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 14 : 18,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade600, Colors.orange.shade400],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isMobile ? 14.5 : 18.5),
                topRight: Radius.circular(isMobile ? 14.5 : 18.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.pending_actions_rounded,
                  color: Colors.white,
                  size: isMobile ? 22 : 26,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: Text(
                    'تسليم مناوبة معلق - ${line.arabicLabel}',
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 15 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handover summary (outgoing operator, time, type, notes)
                _buildInfoSection(
                  context,
                  icon: Icons.person_outline_rounded,
                  title: 'معلومات التسليم',
                  isMobile: isMobile,
                  iconColor: Colors.blue.shade600,
                  children: [
                    if (handover.outgoingOperatorName != null)
                      _buildInfoRow(
                        'المشغل المسلّم',
                        handover.outgoingOperatorName!,
                        isMobile,
                      ),
                    if (handover.createdAtDisplay != null)
                      _buildInfoRow(
                        'وقت التسليم',
                        handover.createdAtDisplay!,
                        isMobile,
                      ),
                    if (handover.notes != null && handover.notes!.isNotEmpty)
                      _buildInfoRow('ملاحظات', handover.notes!, isMobile),
                  ],
                ),
                SizedBox(height: isMobile ? 12 : 16),

                // FALET items
                if (handover.faletItems.isNotEmpty) ...[
                  _buildFaletSection(context, isMobile),
                  SizedBox(height: isMobile ? 16 : 20),
                ],

                // Rejection reasons (for REJECTED/RESOLVED past handovers)
                if (_hasStructuredRejection) ...[
                  _buildRejectionSection(context, isMobile),
                  SizedBox(height: isMobile ? 12 : 16),
                ] else if (_hasLegacyRejection) ...[
                  _buildInfoSection(
                    context,
                    icon: Icons.cancel_outlined,
                    title: 'سبب الرفض',
                    isMobile: isMobile,
                    iconColor: Colors.red.shade600,
                    children: [
                      _buildInfoRow(
                        'ملاحظات',
                        handover.rejectionNotes!,
                        isMobile,
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                ],

                // Receipt notes (for CONFIRMED past handovers)
                if (handover.receiptNotes != null &&
                    handover.receiptNotes!.isNotEmpty) ...[
                  _buildInfoSection(
                    context,
                    icon: Icons.receipt_long_rounded,
                    title: 'ملاحظات الاستلام',
                    isMobile: isMobile,
                    iconColor: Colors.green.shade600,
                    children: [
                      _buildInfoRow(
                        'ملاحظات',
                        handover.receiptNotes!,
                        isMobile,
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                ],

                // Resolve actions — only when incoming operator is authorized
                if (showResolveActions &&
                    (onResolve != null || onReject != null)) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onResolve != null)
                        ElevatedButton.icon(
                          onPressed: isResolving ? null : onResolve,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: isResolving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(
                            'معلومات دقيقة وتأكيد التسليم',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 15 : 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (onResolve != null && onReject != null)
                        SizedBox(height: isMobile ? 10 : 14),
                      if (onReject != null)
                        ElevatedButton.icon(
                          onPressed: isResolving ? null : onReject,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(
                            'تسليم غير دقيق وتأكيد الاستلام',
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 15 : 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// True when the backend returned structured rejection fields (V37+).
  bool get _hasStructuredRejection =>
      handover.rejectionIncorrectQuantity == true ||
      handover.rejectionOtherReason == true ||
      handover.rejectionUndeclaredFalet == true;

  /// True for legacy rejected handovers (pre-V37) that only have plain notes.
  bool get _hasLegacyRejection =>
      !_hasStructuredRejection &&
      handover.rejectionNotes != null &&
      handover.rejectionNotes!.isNotEmpty;

  /// Whether any falet item has an observed quantity (i.e. this is a rejected
  /// handover with "incorrect quantity" data).
  bool get _hasObservedQuantities =>
      handover.faletItems.any((item) => item.observedQuantity != null);

  Widget _buildFaletSection(BuildContext context, bool isMobile) {
    final fontSize = isMobile ? 13.0 : 15.0;
    if (_hasObservedQuantities) {
      // Declared vs Observed table
      return _buildInfoSection(
        context,
        icon: Icons.warning_amber_rounded,
        title: 'عناصر الفالت',
        isMobile: isMobile,
        iconColor: Colors.orange.shade600,
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'المنتج',
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'المُعلنة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'المُلاحظة',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade300, height: 1),
          const SizedBox(height: 4),
          for (final item in handover.faletItems)
            _buildFaletObservedRow(item, isMobile, fontSize),
        ],
      );
    }

    // Simple list (no observed quantities)
    return _buildInfoSection(
      context,
      icon: Icons.warning_amber_rounded,
      title: 'عناصر الفالت',
      isMobile: isMobile,
      iconColor: Colors.orange.shade600,
      children: [
        for (final item in handover.faletItems)
          _buildInfoRow(
            '${ProductType.formatCompactName(item.productTypeName)}${item.lastActiveProduct ? ' (نشط)' : ''}',
            '${item.quantity} عبوة',
            isMobile,
          ),
      ],
    );
  }

  Widget _buildFaletObservedRow(
    HandoverFaletItem item,
    bool isMobile,
    double fontSize,
  ) {
    final observed = item.observedQuantity;
    final mismatch = observed != null && observed != item.quantity;
    final rowColor = mismatch ? Colors.red.shade700 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: mismatch
            ? BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${ProductType.formatCompactName(item.productTypeName)}${item.lastActiveProduct ? ' (نشط)' : ''}',
                style: GoogleFonts.cairo(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: rowColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${item.quantity}',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: rowColor,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                observed != null ? '$observed' : '—',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: rowColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectionSection(BuildContext context, bool isMobile) {
    final fontSize = isMobile ? 12.0 : 13.0;
    return _buildInfoSection(
      context,
      icon: Icons.cancel_outlined,
      title: 'أسباب الرفض',
      isMobile: isMobile,
      iconColor: Colors.red.shade600,
      children: [
        // Rejection reason badges
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (handover.rejectionIncorrectQuantity == true)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  'عدد غير صحيح',
                  style: GoogleFonts.cairo(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            if (handover.rejectionOtherReason == true)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'سبب آخر',
                  style: GoogleFonts.cairo(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            if (handover.rejectionUndeclaredFalet == true)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.deepOrange.shade300),
                ),
                child: Text(
                  'فالت غير مصرح عنه',
                  style: GoogleFonts.cairo(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ),
          ],
        ),
        // Other reason notes text
        if (handover.rejectionOtherReasonNotes != null &&
            handover.rejectionOtherReasonNotes!.isNotEmpty) ...[
          SizedBox(height: isMobile ? 8 : 10),
          _buildInfoRow(
            'تفاصيل',
            handover.rejectionOtherReasonNotes!,
            isMobile,
          ),
        ],
      ],
    );
  }

  Widget _buildInfoSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isMobile,
    required List<Widget> children,
    Color? iconColor,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: iconColor ?? Colors.grey.shade600,
                size: isMobile ? 18 : 22,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 3 : 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 13 : 15,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
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
      ),
    );
  }
}
