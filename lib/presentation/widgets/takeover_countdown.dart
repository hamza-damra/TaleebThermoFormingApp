import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/palletizing_provider.dart';

/// Backend-authoritative countdown for a Line Takeover Request window.
///
/// The remaining time is derived every tick from the backend deadline
/// (`expiresAt` / `handoverExpiresAt`), falling back to `*RemainingSeconds`.
/// This is drift-free and self-corrects after an app resume. When it reaches
/// zero the widget triggers a single line-state refetch so the backend — not
/// the app — decides the timeout outcome.
class TakeoverCountdown extends StatefulWidget {
  final int lineNumber;

  /// `false` → the 10-min PENDING window; `true` → the 5-min post-ACCEPT
  /// handover window.
  final bool handover;

  final Color color;

  const TakeoverCountdown({
    super.key,
    required this.lineNumber,
    required this.color,
    this.handover = false,
  });

  @override
  State<TakeoverCountdown> createState() => _TakeoverCountdownState();
}

class _TakeoverCountdownState extends State<TakeoverCountdown> {
  Timer? _ticker;
  bool _refetchTriggered = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final takeover = provider.getTakeover(widget.lineNumber);

    final remaining = takeover == null
        ? null
        : (widget.handover
              ? takeover.handoverRemaining()
              : takeover.pendingRemaining());

    if (remaining == null) {
      // No backend deadline available — render nothing rather than guess.
      return const SizedBox.shrink();
    }

    if (remaining <= Duration.zero) {
      // Backend is authoritative: ask it for the real (auto-released) status
      // exactly once instead of deciding the timeout locally.
      if (!_refetchTriggered) {
        _refetchTriggered = true;
        _ticker?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.read<PalletizingProvider>().refreshLineState(
              widget.lineNumber,
            );
          }
        });
      }
      return _buildPill('00:00');
    }

    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return _buildPill('$minutes:$seconds');
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: widget.color),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: widget.color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
