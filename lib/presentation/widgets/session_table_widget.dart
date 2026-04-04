import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/session_table_row.dart';

class SessionTableWidget extends StatelessWidget {
  final ProductionLine line;
  final List<SessionTableRow> rows;

  const SessionTableWidget({
    super.key,
    required this.line,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Column(
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
                colors: [line.color, line.color.withValues(alpha: 0.85)],
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
                    Icons.table_chart_outlined,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 16),
                Text(
                  'ملخص الجلسة',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Table content
          if (rows.isEmpty)
            _buildEmptyState(context, isMobile)
          else
            _buildTable(context, isMobile),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: Colors.grey.shade300,
            size: isMobile ? 40 : 48,
          ),
          SizedBox(height: isMobile ? 8 : 12),
          Text(
            'لا توجد بيانات إنتاج في هذه الجلسة',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, bool isMobile) {
    final headerStyle = GoogleFonts.cairo(
      fontSize: isMobile ? 11 : 13,
      fontWeight: FontWeight.bold,
      color: Colors.grey.shade700,
    );
    final cellStyle = GoogleFonts.cairo(
      fontSize: isMobile ? 13 : 15,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );
    final looseStyle = GoogleFonts.cairo(
      fontSize: isMobile ? 13 : 15,
      fontWeight: FontWeight.bold,
      color: Colors.orange.shade700,
    );

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.5),
            1: FlexColumnWidth(1.5),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.5),
          },
          border: TableBorder(
            horizontalInside:
                BorderSide(color: Colors.grey.shade200, width: 1),
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(
                color: line.color.withValues(alpha: 0.06),
              ),
              children: [
                _buildHeaderCell('نوع المنتج', headerStyle, isMobile),
                _buildHeaderCell('المشاتيح', headerStyle, isMobile),
                _buildHeaderCell('العبوات', headerStyle, isMobile),
                _buildHeaderCell('الفالت', headerStyle, isMobile),
              ],
            ),
            // Data rows
            for (final row in rows)
              TableRow(
                decoration: row.hasLooseBalance
                    ? BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.05),
                      )
                    : null,
                children: [
                  _buildCell(ProductType.formatCompactName(row.productTypeName), cellStyle, isMobile),
                  _buildCell(
                    '${row.completedPalletCount}',
                    cellStyle,
                    isMobile,
                    alignment: Alignment.center,
                  ),
                  _buildCell(
                    '${row.completedPackageCount}',
                    cellStyle,
                    isMobile,
                    alignment: Alignment.center,
                  ),
                  _buildCell(
                    '${row.loosePackageCount}',
                    row.hasLooseBalance ? looseStyle : cellStyle,
                    isMobile,
                    alignment: Alignment.center,
                    icon: row.hasLooseBalance
                        ? Icon(
                            Icons.warning_amber_rounded,
                            size: isMobile ? 14 : 16,
                            color: Colors.orange.shade600,
                          )
                        : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, TextStyle style, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 10 : 14,
      ),
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }

  Widget _buildCell(
    String text,
    TextStyle style,
    bool isMobile, {
    Alignment alignment = Alignment.centerRight,
    Widget? icon,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 10 : 14,
      ),
      child: icon != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 4),
                Text(text, style: style),
              ],
            )
          : Align(
              alignment: alignment,
              child: Text(
                text,
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }
}
