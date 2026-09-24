import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/constants/grinding_recommendation_strings.dart';
import '../../core/responsive.dart';
import '../../domain/entities/palletizing_line.dart';
import '../../domain/entities/product_type.dart';

class CreatePalletDialog extends StatefulWidget {
  final PalletizingLine line;
  final ProductType? initialProductType;

  /// Optional override for the default quantity. When set, takes precedence
  /// over `initialProductType.packageQuantity`.
  final int? initialQuantity;

  const CreatePalletDialog({
    super.key,
    required this.line,
    this.initialProductType,
    this.initialQuantity,
  });

  @override
  State<CreatePalletDialog> createState() => _CreatePalletDialogState();
}

class _CreatePalletDialogState extends State<CreatePalletDialog> {
  late ProductType? _plannedProductType;
  late int _quantity;
  late TextEditingController _quantityController;

  // Grinding recommendation — lives only as long as the dialog, so closing
  // it discards the reason.
  bool _recommendGrinding = false;
  final TextEditingController _grindingReasonController =
      TextEditingController();
  String? _grindingReasonError;

  @override
  void initState() {
    super.initState();
    _plannedProductType = widget.initialProductType;
    _quantity =
        widget.initialQuantity ?? _plannedProductType?.packageQuantity ?? 20;
    _quantityController = TextEditingController(text: '$_quantity');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _grindingReasonController.dispose();
    super.dispose();
  }

  /// Resolved server label (lineDisplayName → lineName → abjad ordinal).
  String _resolvedLineLabel() => widget.line.label;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 400.0;
    final spacing = isMobile ? 16.0 : 20.0;

    return AlertDialog(
      title: Text(
        'إنشاء طبلية جديدة - ${_resolvedLineLabel()}',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: widget.line.color,
          fontSize: isMobile ? 16 : 20,
        ),
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 24),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPlannedProductDisplay(context),
              SizedBox(height: spacing),
              _buildQuantityStepper(context),
              SizedBox(height: spacing),
              _buildGrindingRecommendation(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'إلغاء',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _canConfirm() ? _handleConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.line.color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 32,
              vertical: isMobile ? 8 : 12,
            ),
          ),
          child: Text(
            'تأكيد',
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // Read-only label showing the current Thermoforming Production Plan
  // product. NOT a picker — the operator cannot change the product here.
  // Source of truth is `widget.initialProductType`, which the caller derives
  // from `PalletizingProvider.getCurrentPlanItemProductType`.
  Widget _buildPlannedProductDisplay(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع المنتج',
          style: GoogleFonts.cairo(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 14 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _plannedProductType?.productName ?? 'لا يوجد منتج نشط',
                      style: GoogleFonts.cairo(
                        fontSize: fontSize,
                        color: _plannedProductType != null
                            ? Colors.black87
                            : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_plannedProductType?.description != null &&
                        _plannedProductType!.description!.trim().isNotEmpty)
                      Text(
                        _plannedProductType!.description!,
                        style: GoogleFonts.cairo(
                          fontSize: fontSize - 2,
                          color: Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityStepper(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 16.0;
    final iconSize = isMobile ? 32.0 : 40.0;
    final quantityFontSize = isMobile ? 22.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الكمية',
          style: GoogleFonts.cairo(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: isMobile ? 6 : 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _quantity > 1
                    ? () {
                        setState(() {
                          _quantity--;
                          _quantityController.text = '$_quantity';
                        });
                      }
                    : null,
                icon: Icon(
                  Icons.remove_circle,
                  color: widget.line.color,
                  size: iconSize,
                ),
              ),
              SizedBox(width: isMobile ? 8 : 16),
              SizedBox(
                width: isMobile ? 60 : 80,
                child: TextField(
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.cairo(
                    fontSize: quantityFontSize,
                    fontWeight: FontWeight.bold,
                    color: widget.line.color,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  controller: _quantityController,
                  onChanged: (value) {
                    if (value.isEmpty) return;
                    final newValue = int.tryParse(value);
                    if (newValue != null && newValue >= 0) {
                      _quantity = newValue;
                    }
                  },
                ),
              ),
              SizedBox(width: isMobile ? 8 : 16),
              IconButton(
                onPressed: () {
                  setState(() {
                    _quantity++;
                    _quantityController.text = '$_quantity';
                  });
                },
                icon: Icon(
                  Icons.add_circle,
                  color: widget.line.color,
                  size: iconSize,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // «توصية بالجرش» switch (default off); when on, a required reason.
  Widget _buildGrindingRecommendation(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _recommendGrinding
                  ? Colors.orange.shade400
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            key: const Key('grindingRecommendationSwitch'),
            value: _recommendGrinding,
            onChanged: (value) {
              setState(() {
                _recommendGrinding = value;
                _grindingReasonError = null;
              });
            },
            activeThumbColor: Colors.orange.shade700,
            secondary: Icon(
              Icons.recycling_rounded,
              color: _recommendGrinding
                  ? Colors.orange.shade700
                  : Colors.grey.shade500,
            ),
            title: Text(
              GrindingRecommendationStrings.switchLabel,
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (_recommendGrinding) ...[
          SizedBox(height: isMobile ? 10 : 12),
          TextField(
            key: const Key('grindingReasonField'),
            controller: _grindingReasonController,
            minLines: 2,
            maxLines: 4,
            maxLength: GrindingRecommendationStrings.reasonMaxLength,
            textInputAction: TextInputAction.newline,
            style: GoogleFonts.cairo(fontSize: fontSize),
            decoration: InputDecoration(
              labelText: GrindingRecommendationStrings.reasonLabel,
              labelStyle: GoogleFonts.cairo(fontSize: fontSize - 1),
              errorText: _grindingReasonError,
              errorStyle: GoogleFonts.cairo(),
              errorMaxLines: 2,
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) {
              if (_grindingReasonError != null) {
                setState(() => _grindingReasonError = null);
              }
            },
          ),
        ],
      ],
    );
  }

  bool _canConfirm() {
    return _plannedProductType != null && _quantity > 0;
  }

  void _handleConfirm() {
    String? grindingReason;
    if (_recommendGrinding) {
      final error = GrindingRecommendationStrings.validateReason(
        _grindingReasonController.text,
      );
      if (error != null) {
        // Nothing is sent until the reason is valid.
        setState(() => _grindingReasonError = error);
        return;
      }
      grindingReason = _grindingReasonController.text.trim();
    }

    // Return the quantity (and the grinding reason when recommended). The
    // product is forced by the caller from the current plan item — the
    // dialog has no picker and must not surface a product id to downstream
    // code.
    Navigator.of(
      context,
    ).pop({'quantity': _quantity, 'grindingReason': ?grindingReason});
  }
}
