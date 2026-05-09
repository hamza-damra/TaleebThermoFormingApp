import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/line_handover_info.dart';

/// Result returned from the handover rejection dialog.
class HandoverRejectResult {
  final bool incorrectQuantity;
  final bool otherReason;
  final String? otherReasonNotes;
  final bool undeclaredFaletFound;
  final int? undeclaredFaletObservedQuantity;
  final String? undeclaredFaletNotes;

  /// Maps faletSnapshotId → observedQuantity.
  final List<Map<String, dynamic>>? itemObservations;

  const HandoverRejectResult({
    required this.incorrectQuantity,
    required this.otherReason,
    this.otherReasonNotes,
    this.undeclaredFaletFound = false,
    this.undeclaredFaletObservedQuantity,
    this.undeclaredFaletNotes,
    this.itemObservations,
  });
}

/// Rejection reason: radio selection.
enum _RejectReason {
  incorrectQuantity, // عدد غير صحيح — user enters qty > 0
  noFalet, // لا يوجد فالت — qty = 0 automatically
}

class HandoverRejectDialog extends StatefulWidget {
  final List<HandoverFaletItem> faletItems;

  const HandoverRejectDialog({super.key, required this.faletItems});

  /// Show the dialog and return the result, or null if cancelled.
  static Future<HandoverRejectResult?> show({
    required BuildContext context,
    required List<HandoverFaletItem> faletItems,
  }) {
    return showDialog<HandoverRejectResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HandoverRejectDialog(faletItems: faletItems),
    );
  }

  @override
  State<HandoverRejectDialog> createState() => _HandoverRejectDialogState();
}

class _HandoverRejectDialogState extends State<HandoverRejectDialog> {
  _RejectReason? _selectedReason;
  final _quantityController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selectedReason == null) return false;
    if (_selectedReason == _RejectReason.incorrectQuantity) {
      final qty = int.tryParse(_quantityController.text.trim());
      return qty != null && qty > 0;
    }
    // "لا يوجد فالت" — always valid once selected
    return true;
  }

  void _handleSubmit() {
    if (!_canSubmit) return;

    // Determine the FALET quantity based on the selected reason
    final int faletQuantity;
    if (_selectedReason == _RejectReason.noFalet) {
      faletQuantity = 0;
    } else {
      faletQuantity = int.parse(_quantityController.text.trim());
    }

    // Local mirror of HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH: if the same qty
    // is applied to every snapshot and matches the declared qty for all of
    // them, the backend will refuse — surface the message immediately instead
    // of round-tripping.
    if (widget.faletItems.isNotEmpty &&
        widget.faletItems.every((i) => i.quantity == faletQuantity)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الكمية المرصودة تطابق الكمية المصرح عنها. لا يمكن الرفض.',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Build per-item observations. `faletSnapshotId` MUST be the snapshot row's
    // primary key — sending the FALET state FK here is the production-#79 bug
    // and now triggers HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH on the backend.
    List<Map<String, dynamic>>? observations;
    if (widget.faletItems.isNotEmpty) {
      observations = widget.faletItems
          .map(
            (item) => {
              'faletSnapshotId': item.faletSnapshotId,
              'observedQuantity': faletQuantity,
            },
          )
          .toList();
    }

    Navigator.of(context).pop(
      HandoverRejectResult(
        incorrectQuantity: true,
        otherReason: false,
        otherReasonNotes: null,
        undeclaredFaletFound: false,
        undeclaredFaletObservedQuantity: null,
        undeclaredFaletNotes: null,
        itemObservations: observations,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = isMobile ? screenWidth * 0.95 : 520.0;
    final fontSize = isMobile ? 13.0 : 14.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'رفض التسليم',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
                fontSize: isMobile ? 16 : 18,
              ),
            ),
          ),
        ],
      ),
      contentPadding: EdgeInsets.all(isMobile ? 16 : 20),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اختر سبب الرفض:',
                style: GoogleFonts.cairo(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),

              // ── Option A: عدد غير صحيح ──
              _buildRadioOption(
                value: _RejectReason.incorrectQuantity,
                label: 'عدد غير صحيح',
                icon: Icons.numbers_rounded,
                activeColor: Colors.red.shade600,
                isMobile: isMobile,
              ),

              // ── Option B: لا يوجد فالت ──
              _buildRadioOption(
                value: _RejectReason.noFalet,
                label: 'لا يوجد فالت',
                icon: Icons.remove_circle_outline_rounded,
                activeColor: Colors.orange.shade700,
                isMobile: isMobile,
              ),

              // ── Quantity input (only for عدد غير صحيح) ──
              if (_selectedReason == _RejectReason.incorrectQuantity) ...[
                const SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.all(isMobile ? 10 : 14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'كمية الفالت المُلاحظة',
                        style: GoogleFonts.cairo(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: isMobile ? 48 : 52,
                        child: TextField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textAlign: TextAlign.center,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'أدخل العدد',
                            hintStyle: GoogleFonts.cairo(
                              fontSize: fontSize,
                              color: Colors.grey.shade500,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.red.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.red.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.red.shade600,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          style: GoogleFonts.cairo(
                            fontSize: fontSize + 4,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'يجب أن يكون العدد أكبر من صفر',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : 12,
                          color: Colors.red.shade400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              // ── Info banner for "لا يوجد فالت" ──
              if (_selectedReason == _RejectReason.noFalet) ...[
                const SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.all(isMobile ? 10 : 14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم الإبلاغ بعدم وجود فالت على الخط',
                          style: GoogleFonts.cairo(
                            fontSize: fontSize,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _handleSubmit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.red.shade200,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'تأكيد الرفض',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioOption({
    required _RejectReason value,
    required String label,
    required IconData icon,
    required Color activeColor,
    required bool isMobile,
  }) {
    final isSelected = _selectedReason == value;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? activeColor.withValues(alpha: 0.08)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? activeColor.withValues(alpha: 0.4)
              : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedReason = value;
            if (value == _RejectReason.noFalet) {
              _quantityController.clear();
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12,
            vertical: isMobile ? 10 : 12,
          ),
          child: Row(
            children: [
              Radio<_RejectReason>(
                value: value,
                groupValue: _selectedReason,
                onChanged: (v) {
                  setState(() {
                    _selectedReason = v;
                    if (v == _RejectReason.noFalet) {
                      _quantityController.clear();
                    }
                  });
                },
                activeColor: activeColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                color: isSelected ? activeColor : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? activeColor : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
