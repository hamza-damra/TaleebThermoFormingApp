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
                    if (handover.handoverType != null)
                      _buildInfoRow(
                        'نوع التسليم',
                        _handoverTypeLabel(handover.handoverType!),
                        isMobile,
                      ),
                    if (handover.notes != null && handover.notes!.isNotEmpty)
                      _buildInfoRow('ملاحظات', handover.notes!, isMobile),
                  ],
                ),
                SizedBox(height: isMobile ? 12 : 16),

                // Incomplete pallet
                if (handover.incompletePallet != null) ...[
                  _buildInfoSection(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: 'طبلية ناقصة',
                    isMobile: isMobile,
                    children: [
                      _buildInfoRow(
                        'المنتج',
                        ProductType.formatCompactName(
                          handover.incompletePallet!.productTypeName,
                        ),
                        isMobile,
                      ),
                      _buildInfoRow(
                        'الكمية',
                        '${handover.incompletePallet!.quantity}',
                        isMobile,
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                ],

                // Loose balances
                if (handover.looseBalances.isNotEmpty) ...[
                  _buildInfoSection(
                    context,
                    icon: Icons.warning_amber_rounded,
                    title: 'ملخص الفالت',
                    isMobile: isMobile,
                    iconColor: Colors.orange.shade600,
                    children: [
                      for (final lb in handover.looseBalances)
                        _buildInfoRow(
                          ProductType.formatCompactName(lb.productTypeName),
                          '${lb.loosePackageCount} عبوة',
                          isMobile,
                        ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 16 : 20),
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

  String _handoverTypeLabel(String type) {
    switch (type) {
      case 'NONE':
        return 'تسليم نظيف';
      case 'INCOMPLETE_PALLET_ONLY':
        return 'طبليات ناقصة فقط';
      case 'LOOSE_BALANCES_ONLY':
        return 'فالت فقط';
      case 'BOTH':
        return 'طبليات ناقصة وفالت';
      default:
        return type;
    }
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
