import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/responsive.dart';
import '../../domain/entities/operator.dart';
import '../../domain/entities/product_type.dart';
import '../../domain/entities/production_line.dart' as entity;
import '../providers/palletizing_provider.dart';
import 'create_pallet_dialog.dart';
import 'pallet_success_dialog.dart';
import 'summary_card.dart';

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
    final isMobile = ResponsiveHelper.isMobile(context);
    final horizontalPadding = isMobile ? 16.0 : 24.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      color: line.lightColor,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: isMobile ? 20 : 32),
                      if (ResponsiveHelper.isDesktop(context)) ...[
                        _buildHeader(context),
                        const SizedBox(height: 32),
                      ],
                      _buildFormCard(context),
                      SizedBox(height: isMobile ? 20 : 28),
                      _buildSummaryCard(context),
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
            _buildOperatorField(context),
            SizedBox(height: isMobile ? 20 : 28),
            _buildProductField(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOperatorField(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final selectedOperator = provider.getSelectedOperator(line.number);

    if (provider.operators.isEmpty) {
      return _buildFieldContainer(
        context: context,
        label: 'اسم المشغل',
        icon: Icons.person_outline_rounded,
        child: _buildWarningBox(
          context,
          'لا يوجد مشغلين - يرجى إضافتهم من لوحة الإدارة',
        ),
      );
    }

    return _buildFieldContainer(
      context: context,
      label: 'اسم المشغل',
      icon: Icons.person_outline_rounded,
      child: DropdownButtonFormField<Operator>(
        key: ValueKey('operator_${line.number}_${provider.operators.length}'),
        value: selectedOperator,
        isExpanded: true,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: line.color,
          size: isMobile ? 24 : 28,
        ),
        decoration: _buildInputDecoration(context, 'اختر المشغل'),
        dropdownColor: Colors.white,
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 15 : 17,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
        items: provider.operators.map((operator) {
          return DropdownMenuItem<Operator>(
            value: operator,
            child: Text(
              operator.name,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w500,
                height: 1.2, // Added height to prevent clipping
              ),
            ),
          );
        }).toList(),
        onChanged: (value) {
          context.read<PalletizingProvider>().selectOperator(line.number, value);
        },
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
      child: DropdownButtonFormField<ProductType>(
        key: ValueKey('product_${line.number}_${provider.productTypes.length}'),
        value: selectedProductType,
        isExpanded: true,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: line.color,
          size: isMobile ? 24 : 28,
        ),
        decoration: _buildInputDecoration(context, 'اختر نوع المنتج'),
        dropdownColor: Colors.white,
        style: GoogleFonts.cairo(
          fontSize: isMobile ? 15 : 17,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
        items: provider.productTypes.map((productType) {
          return DropdownMenuItem<ProductType>(
            value: productType,
            child: Text(
              productType.name,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w500,
                height: 1.2, // Added height to prevent clipping
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (value) async {
          if (value == null) return;
          final confirmed = await _showProductTypeConfirmationDialog(context, value);
          if (confirmed == true && context.mounted) {
            context.read<PalletizingProvider>().selectProductType(line.number, value);
          }
        },
      ),
    );
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

  InputDecoration _buildInputDecoration(BuildContext context, String hint) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.cairo(
        fontSize: isMobile ? 14 : 16,
        color: Colors.grey.shade400,
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      isDense: false,
      contentPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 20,
        vertical: isMobile ? 22 : 28, // Even larger vertical padding
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line.color, width: 2),
      ),
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

    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? 340 : 420),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header icon
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
              // Product info card
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
                  border: Border.all(color: line.color.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      productType.name,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 17 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 8 : 10),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'اللون: ${productType.color}',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 13 : 15,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              // Product Image
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: isMobile ? 40 : 52,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: isMobile ? 8 : 10),
                      Text(
                        'صورة المنتج',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 13 : 15,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 24 : 32),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                        ),
                        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
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

  Widget _buildSummaryCard(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();

    final palletCount = provider.getPalletCount(line.number);
    final selectedProductType = provider.getSelectedProductType(line.number);
    final packageCount = selectedProductType != null
        ? palletCount * selectedProductType.packageQuantity
        : 0;

    return SummaryCard(
      line: line,
      palletCount: palletCount,
      packageCount: packageCount,
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);

    return ElevatedButton(
      onPressed: provider.isCreating ? null : () => _showCreateDialog(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: line.color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: line.color.withValues(alpha: 0.5),
        minimumSize: Size(double.infinity, isMobile ? 60 : 68),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: provider.isCreating
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
                Icon(Icons.add_circle_outline_rounded, size: isMobile ? 22 : 26),
                SizedBox(width: isMobile ? 8 : 12),
                Text(
                  'إنشاء مشتاح جديد',
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
    final initialOperator = provider.getSelectedOperator(line.number);
    final initialProductType = provider.getSelectedProductType(line.number);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CreatePalletDialog(
        line: line,
        operators: provider.operators,
        productTypes: provider.productTypes,
        initialOperator: initialOperator,
        initialProductType: initialProductType,
      ),
    );

    if (result != null && context.mounted) {
      final operator = result['operator'] as Operator;
      final productType = result['productType'] as ProductType;
      final quantity = result['quantity'] as int;

      try {
        final palletResponse = await context
            .read<PalletizingProvider>()
            .createPallet(
              operatorId: operator.id,
              productTypeId: productType.id,
              productionLineId: productionLineEntity?.id ?? line.number,
              lineNumber: line.number,
              quantity: quantity,
            );

        if (context.mounted) {
          _showSuccessDialog(context, palletResponse);
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
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في إنشاء المشتاح', style: GoogleFonts.cairo()),
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
      builder: (context) =>
          PalletSuccessDialog(pallet: palletResponse, lineColor: line.color),
    );
  }
}
