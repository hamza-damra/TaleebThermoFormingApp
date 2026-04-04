import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../domain/entities/line_handover_info.dart';
import '../providers/palletizing_provider.dart';

class LineAuthOverlay extends StatefulWidget {
  final ProductionLine line;

  const LineAuthOverlay({super.key, required this.line});

  @override
  State<LineAuthOverlay> createState() => _LineAuthOverlayState();
}

class _LineAuthOverlayState extends State<LineAuthOverlay> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final isAuthorizing = provider.isLineAuthorizing(widget.line.number);
    final authState = provider.getLineAuth(widget.line.number);
    final error = authState?.authError;
    final lineUiMode = provider.getLineUiMode(widget.line.number);
    final isPendingIncoming = lineUiMode == 'PENDING_HANDOVER_NEEDS_INCOMING';
    final pendingHandover = provider.getPendingHandover(widget.line.number);

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 40),
            child: Container(
              constraints: BoxConstraints(maxWidth: isMobile ? 360 : 420),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.line.color.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 24 : 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pending handover summary (if waiting for incoming)
                    if (isPendingIncoming && pendingHandover != null) ...[
                      _buildPendingHandoverSummary(
                        context,
                        pendingHandover,
                        isMobile,
                      ),
                      SizedBox(height: isMobile ? 16 : 20),
                    ],

                    // Icon
                    Container(
                      padding: EdgeInsets.all(isMobile ? 16 : 20),
                      decoration: BoxDecoration(
                        color: isPendingIncoming
                            ? Colors.orange.withValues(alpha: 0.1)
                            : widget.line.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPendingIncoming
                            ? Icons.swap_horiz_rounded
                            : Icons.lock_outline_rounded,
                        color: isPendingIncoming
                            ? Colors.orange.shade700
                            : widget.line.color,
                        size: isMobile ? 36 : 44,
                      ),
                    ),
                    SizedBox(height: isMobile ? 16 : 20),

                    // Title
                    Text(
                      isPendingIncoming
                          ? 'في انتظار المشغل القادم'
                          : 'تفويض المشغل',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      isPendingIncoming
                          ? 'أدخل رمز المشغل القادم لمراجعة التسليم'
                          : 'أدخل رمز المشغل المكون من 4 أرقام لتفعيل ${widget.line.arabicLabel}',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 24 : 32),

                    // PIN Input
                    TextField(
                      controller: _pinController,
                      focusNode: _focusNode,
                      enabled: !isAuthorizing,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 28 : 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                        color: widget.line.color,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '● ● ● ●',
                        hintStyle: GoogleFonts.cairo(
                          fontSize: isMobile ? 24 : 28,
                          color: Colors.grey.shade300,
                          letterSpacing: 8,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: error != null
                                ? Colors.red.shade300
                                : Colors.grey.shade300,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: error != null
                                ? Colors.red.shade300
                                : Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: error != null
                                ? Colors.red
                                : widget.line.color,
                            width: 2,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isMobile ? 16 : 20,
                          horizontal: 16,
                        ),
                      ),
                      onSubmitted: isAuthorizing
                          ? null
                          : (_) => _handleSubmit(),
                      onChanged: (_) {
                        // Clear error when user starts typing
                        if (error != null) {
                          provider.clearLineAuthError(widget.line.number);
                        }
                      },
                    ),
                    SizedBox(height: isMobile ? 8 : 12),

                    // Error message
                    if (error != null)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isMobile ? 10 : 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red.shade600,
                              size: isMobile ? 18 : 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error,
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 13 : 14,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(height: isMobile ? 20 : 24),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isAuthorizing ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.line.color,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: widget.line.color.withValues(
                            alpha: 0.5,
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 16 : 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: isAuthorizing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'تأكيد',
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 18 : 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingHandoverSummary(
    BuildContext context,
    LineHandoverInfo handover,
    bool isMobile,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pending_actions_rounded,
                color: Colors.orange.shade700,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تسليم مناوبة معلق',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 10),
          if (handover.outgoingOperatorName != null)
            _buildSummaryRow(
              'المشغل المسلّم',
              handover.outgoingOperatorName!,
              isMobile,
            ),
          if (handover.handoverType != null)
            _buildSummaryRow(
              'نوع التسليم',
              _handoverTypeLabel(handover.handoverType!),
              isMobile,
            ),
          if (handover.createdAtDisplay != null)
            _buildSummaryRow('الوقت', handover.createdAtDisplay!, isMobile),
          if (handover.hasIncompletePallet)
            _buildSummaryRow('طبلية ناقصة', 'نعم', isMobile),
          if (handover.looseBalanceCount > 0)
            _buildSummaryRow(
              'أرصدة فرطة',
              '${handover.looseBalanceCount} نوع',
              isMobile,
            ),
          if (handover.notes != null && handover.notes!.isNotEmpty)
            _buildSummaryRow('ملاحظات', handover.notes!, isMobile),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 2 : 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 12 : 13,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
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

  void _handleSubmit() {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      final provider = context.read<PalletizingProvider>();
      // Manually set a local validation error
      provider.clearLineAuthError(widget.line.number);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يجب إدخال 4 أرقام', style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final provider = context.read<PalletizingProvider>();
    provider.authorizeLineWithPin(widget.line.number, pin).then((success) {
      if (success && mounted) {
        _pinController.clear();
      } else if (!success && mounted) {
        _pinController.clear();
        _focusNode.requestFocus();
      }
    });
  }
}
