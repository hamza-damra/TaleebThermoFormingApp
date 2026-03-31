import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/handover.dart';
import '../../domain/entities/operator.dart';
import 'searchable_picker_dialog.dart';

enum PendingHandoverAction { confirm, reject }

class PendingHandoverDialog extends StatefulWidget {
  final Handover handover;
  final bool isProcessing;
  final List<Operator> operators;
  final bool isLoadingOperators;
  final void Function(int operatorId)? onConfirm;
  final void Function(int operatorId)? onReject;

  const PendingHandoverDialog({
    super.key,
    required this.handover,
    required this.operators,
    this.isProcessing = false,
    this.isLoadingOperators = false,
    this.onConfirm,
    this.onReject,
  });

  @override
  State<PendingHandoverDialog> createState() => _PendingHandoverDialogState();
}

class _PendingHandoverDialogState extends State<PendingHandoverDialog> {
  Operator? _selectedOperator;

  bool get _canAct =>
      !widget.isProcessing &&
      !widget.isLoadingOperators &&
      _selectedOperator != null;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 500.0;
    final fontSize = isMobile ? 13.0 : 14.0;
    final titleSize = isMobile ? 16.0 : 18.0;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تسليم مناوبة معلق',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                  fontSize: titleSize,
                ),
              ),
            ),
          ],
        ),
        contentPadding: EdgeInsets.all(isMobile ? 12 : 20),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.handover.message != null &&
                    widget.handover.message!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.block, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.handover.message!,
                            style: GoogleFonts.cairo(
                              fontSize: fontSize,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildInfoCard(isMobile, fontSize),
                const SizedBox(height: 12),
                _buildOperatorSelector(isMobile, fontSize),
                const SizedBox(height: 12),
                Text(
                  'العناصر المسلمة:',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize + 1,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.handover.items.map(
                  (item) => _buildItemRow(item, isMobile, fontSize),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إجمالي الكمية:',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize,
                        ),
                      ),
                      Text(
                        '${widget.handover.totalQuantity}',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize + 2,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.handover.availableActions.isEmpty ||
              widget.handover.availableActions.contains('DISPUTE'))
            TextButton(
              onPressed: _canAct && widget.onReject != null
                  ? () => widget.onReject!(_selectedOperator!.id)
                  : null,
              child: Text(
                'رفض',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 16,
                  color: _canAct ? Colors.red : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (widget.handover.availableActions.isEmpty ||
              widget.handover.availableActions.contains('CONFIRM'))
            ElevatedButton(
              onPressed: _canAct && widget.onConfirm != null
                  ? () => widget.onConfirm!(_selectedOperator!.id)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 32,
                  vertical: isMobile ? 8 : 12,
                ),
              ),
              child: widget.isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'تأكيد الاستلام',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildOperatorSelector(bool isMobile, double fontSize) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اختر اسمك كمشغّل مستلم:',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.isLoadingOperators)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (widget.operators.isEmpty)
            Text(
              'لا يوجد مشغّلين متاحين',
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                color: Colors.red.shade600,
              ),
            )
          else
            InkWell(
              onTap: widget.isProcessing
                  ? null
                  : () async {
                      final selected =
                          await SearchablePickerDialog.show<Operator>(
                        context: context,
                        title: 'اختر المشغّل',
                        searchHint: 'ابحث عن المشغل...',
                        items: widget.operators,
                        selectedItem: _selectedOperator,
                        displayTextExtractor: (op) => op.displayLabel,
                        searchMatcher: (op, query) {
                          final queryLower = query.toLowerCase();
                          return op.name.toLowerCase().contains(queryLower) ||
                              op.code.toLowerCase().contains(queryLower) ||
                              op.displayLabel.toLowerCase().contains(queryLower);
                        },
                        themeColor: Colors.blue,
                      );
                      if (selected != null) {
                        setState(() {
                          _selectedOperator = selected;
                        });
                      }
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedOperator?.displayLabel ?? 'اختر المشغّل',
                        style: GoogleFonts.cairo(
                          fontSize: fontSize,
                          color: _selectedOperator != null
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: widget.isProcessing
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
          if (_selectedOperator == null &&
              !widget.isLoadingOperators &&
              widget.operators.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'يجب اختيار المشغّل قبل التأكيد أو الرفض',
                style: GoogleFonts.cairo(
                  fontSize: fontSize - 1,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isMobile, double fontSize) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'المشغل المسلم:',
            widget.handover.outgoingOperatorName,
            fontSize,
          ),
          const SizedBox(height: 6),
          _buildInfoRow(
            'المناوبة:',
            widget.handover.outgoingShiftDisplayNameAr,
            fontSize,
          ),
          const SizedBox(height: 6),
          _buildInfoRow('التاريخ:', widget.handover.createdAtDisplay, fontSize),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, double fontSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: fontSize,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(dynamic item, bool isMobile, double fontSize) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.factory_outlined,
                size: 16,
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.productionLineName,
                  style: GoogleFonts.cairo(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productTypeName,
                  style: GoogleFonts.cairo(fontSize: fontSize),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.quantity}',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
              if (item.scannedValue != null &&
                  item.scannedValue!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.qr_code, size: 16, color: Colors.grey.shade500),
              ],
            ],
          ),
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.notes!,
                    style: GoogleFonts.cairo(
                      fontSize: fontSize - 1,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
