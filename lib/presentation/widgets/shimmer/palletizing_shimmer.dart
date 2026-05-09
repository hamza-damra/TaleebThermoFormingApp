import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';

/// Shimmer loading skeleton for the main palletizing screen.
/// Mirrors the exact structure of ProductionLineSection for a seamless loading experience.
class PalletizingShimmer extends StatelessWidget {
  final ProductionLine line;

  const PalletizingShimmer({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final horizontalPadding = isMobile ? 16.0 : 24.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Skeletonizer(
      effect: ShimmerEffect(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        duration: const Duration(milliseconds: 1500),
      ),
      child: Container(
        color: line.lightColor,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: isMobile ? 20 : 32),
                        if (ResponsiveHelper.isDesktop(context)) ...[
                          _buildHeaderSkeleton(context),
                          const SizedBox(height: 32),
                        ],
                        _buildFormCardSkeleton(context),
                        SizedBox(height: isMobile ? 20 : 28),
                        _buildSummaryCardSkeleton(context),
                        SizedBox(height: isMobile ? 24 : 32),
                      ],
                    ),
                  ),
                ),
              ),
              // Fixed bottom button skeleton
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
                  child: _buildCreateButtonSkeleton(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 28),
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Bone.text(words: 2, style: TextStyle(fontSize: 26)),
    );
  }

  Widget _buildFormCardSkeleton(BuildContext context) {
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
            _buildFieldSkeleton(context),
            SizedBox(height: isMobile ? 20 : 28),
            _buildFieldSkeleton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldSkeleton(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row with icon
        Row(
          children: [
            Bone.square(
              size: isMobile ? 30 : 38,
              borderRadius: BorderRadius.circular(8),
            ),
            SizedBox(width: isMobile ? 10 : 12),
            Bone.text(words: 2, style: TextStyle(fontSize: isMobile ? 15 : 18)),
          ],
        ),
        SizedBox(height: isMobile ? 12 : 14),
        // Input field skeleton
        Container(
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
                child: Bone.text(
                  words: 2,
                  style: TextStyle(fontSize: isMobile ? 15 : 17),
                ),
              ),
              Bone.icon(size: isMobile ? 24 : 28),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCardSkeleton(BuildContext context) {
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
          // Header skeleton
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 14 : 18,
            ),
            decoration: BoxDecoration(
              color: line.color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isMobile ? 16 : 20),
                topRight: Radius.circular(isMobile ? 16 : 20),
              ),
            ),
            child: Row(
              children: [
                Bone.square(
                  size: isMobile ? 36 : 44,
                  borderRadius: BorderRadius.circular(10),
                ),
                SizedBox(width: isMobile ? 12 : 16),
                Bone.text(
                  words: 2,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 20,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Stats content skeleton
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Row(
              children: [
                Expanded(child: _buildStatCardSkeleton(context)),
                SizedBox(width: isMobile ? 12 : 20),
                Expanded(child: _buildStatCardSkeleton(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardSkeleton(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line.color.withValues(alpha: 0.12), width: 1),
      ),
      child: Column(
        children: [
          // Icon circle
          Bone.circle(size: isMobile ? 44 : 52),
          SizedBox(height: isMobile ? 12 : 16),
          // Value
          Bone.text(words: 1, style: TextStyle(fontSize: isMobile ? 28 : 36)),
          SizedBox(height: isMobile ? 4 : 6),
          // Label
          Bone.text(words: 1, style: TextStyle(fontSize: isMobile ? 13 : 15)),
        ],
      ),
    );
  }

  Widget _buildCreateButtonSkeleton(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      height: isMobile ? 60 : 68,
      decoration: BoxDecoration(
        color: line.color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Bone.icon(size: isMobile ? 22 : 26),
          SizedBox(width: isMobile ? 8 : 12),
          Bone.text(words: 2, style: TextStyle(fontSize: isMobile ? 18 : 21)),
        ],
      ),
    );
  }
}

/// Shimmer loading skeleton for the tablet/desktop layout with two production lines.
class PalletizingShimmerDualPane extends StatelessWidget {
  const PalletizingShimmerDualPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: PalletizingShimmer(line: ProductionLine.line2)),
        Container(width: 2, color: Colors.grey.shade300),
        Expanded(child: PalletizingShimmer(line: ProductionLine.line1)),
      ],
    );
  }
}

/// Shimmer for the mobile tab layout (single line at a time).
class PalletizingShimmerMobile extends StatelessWidget {
  final ProductionLine line;

  const PalletizingShimmerMobile({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: line.lightColor,
      child: PalletizingShimmer(line: line),
    );
  }
}
