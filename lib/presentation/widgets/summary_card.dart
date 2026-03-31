import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';

class SummaryCard extends StatelessWidget {
  final ProductionLine line;
  final int palletCount;
  final int packageCount;

  const SummaryCard({
    super.key,
    required this.line,
    required this.palletCount,
    this.packageCount = 0,
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
                    Icons.assessment_outlined,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 16),
                Text(
                  'ملخص ${line.arabicLabel}',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.inventory_2_rounded,
                    label: 'المشاتيح',
                    value: '$palletCount',
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 20),
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.widgets_rounded,
                    label: 'العبوات',
                    value: '$packageCount',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: line.color.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: line.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: line.color,
              size: isMobile ? 24 : 28,
            ),
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 28 : 36,
              fontWeight: FontWeight.bold,
              color: line.color,
              height: 1,
            ),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
