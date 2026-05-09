import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../providers/palletizing_provider.dart';

/// State A overlay: line is not yet opened by the Thermoforming operator.
/// Shows the same modal silhouette as the legacy operator-PIN overlay so the
/// visual continuity for floor users is preserved.
class ThermoformingWaitingCard extends StatefulWidget {
  final ProductionLine line;

  const ThermoformingWaitingCard({super.key, required this.line});

  @override
  State<ThermoformingWaitingCard> createState() =>
      _ThermoformingWaitingCardState();
}

class _ThermoformingWaitingCardState extends State<ThermoformingWaitingCard> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await context.read<PalletizingProvider>().refreshLineState(
      widget.line.number,
    );
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

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
                        Icons.hourglass_top_rounded,
                        color: widget.line.color,
                        size: isMobile ? 36 : 44,
                      ),
                    ),
                    SizedBox(height: isMobile ? 16 : 20),
                    Text(
                      'بانتظار بدء المناوبة من المشغّل',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'سيتم فتح الخط تلقائيًا بعد بدء المناوبة من تطبيق التشكيل الحراري',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 14 : 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isRefreshing ? null : _handleRefresh,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.line.color,
                          side: BorderSide(
                            color: widget.line.color,
                            width: 1.5,
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 14 : 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isRefreshing
                            ? SizedBox(
                                width: isMobile ? 18 : 20,
                                height: isMobile ? 18 : 20,
                                child: CircularProgressIndicator(
                                  color: widget.line.color,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                size: isMobile ? 20 : 24,
                              ),
                        label: Text(
                          'تحديث',
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 16 : 18,
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
