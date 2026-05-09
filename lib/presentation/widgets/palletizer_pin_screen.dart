import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// State B overlay: line is open (Thermoforming operator authorized) but no
/// palletizer session exists yet for this device. Authenticates the
/// المُشَتِّح with their PIN. Re-uses the visual silhouette of the legacy
/// operator-PIN overlay (rounded modal, line-color accent, 4-digit obscured
/// TextField, full-width primary CTA) so floor users do not need retraining.
class PalletizerPinScreen extends StatefulWidget {
  final ProductionLine line;

  const PalletizerPinScreen({super.key, required this.line});

  @override
  State<PalletizerPinScreen> createState() => _PalletizerPinScreenState();
}

class _PalletizerPinScreenState extends State<PalletizerPinScreen> {
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

  void _handleSubmit() {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
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
    provider.palletizerAuth(widget.line.number, pin).then((success) {
      if (!mounted) return;
      _pinController.clear();
      if (!success) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final isMobile = ResponsiveHelper.isMobile(context);
    final isAuthenticating = provider.isPalletizerAuthenticating(
      widget.line.number,
    );
    final error = provider.getPalletizerAuthError(widget.line.number);

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
                    Container(
                      padding: EdgeInsets.all(isMobile ? 16 : 20),
                      decoration: BoxDecoration(
                        color: widget.line.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.badge_outlined,
                        color: widget.line.color,
                        size: isMobile ? 36 : 44,
                      ),
                    ),
                    SizedBox(height: isMobile ? 16 : 20),
                    Text(
                      'تسجيل دخول المُشَتِّح',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'سجّل دخولك كموظف طبليات للبدء بتسجيل الطبليات',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    TextField(
                      controller: _pinController,
                      focusNode: _focusNode,
                      enabled: !isAuthenticating,
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
                      onSubmitted: isAuthenticating
                          ? null
                          : (_) => _handleSubmit(),
                      onChanged: (_) {
                        if (error != null) {
                          provider.clearPalletizerAuthError(widget.line.number);
                        }
                      },
                    ),
                    SizedBox(height: isMobile ? 8 : 12),
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isAuthenticating ? null : _handleSubmit,
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
                        child: isAuthenticating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'دخول',
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
}
