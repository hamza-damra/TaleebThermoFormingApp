import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/constants/biometric_login_strings.dart';
import '../../domain/entities/biometric_login.dart';
import '../providers/biometric_login_controller.dart';
import '../providers/palletizing_provider.dart';
import 'plan_item_close_request_dialog.dart' show closeOwnRoute;

/// The fingerprint dialog of the biometric login gate (handoff §5), opened by
/// the palletizer PIN screen when the login is refused with a `BIOMETRIC_*`
/// 403. It owns one [BiometricLoginController] — and so the attempt token —
/// for exactly its own lifetime.
///
/// There is no way around the check: no skip, no PIN-only path. It cannot be
/// dismissed by tapping outside (shown with `barrierDismissible: false`); the
/// back button acts as «إلغاء» where «إلغاء» is offered. It closes itself on
/// success, on a non-biometric refusal of the re-submitted login (the PIN
/// screen shows that error), and when the line no longer needs a palletizer
/// login (someone else logged in, the shift ended, the line was switched
/// off).
class BiometricLoginDialog extends StatefulWidget {
  final int lineId;
  final BiometricDenial denial;
  final BiometricStatusFetcher fetchStatus;

  /// Re-submits the original login (same PIN, same line).
  final Future<PalletizerAuthOutcome> Function() resubmit;

  /// Overrides the network backoff (tests).
  final Duration Function(int consecutiveFailures)? backoff;

  const BiometricLoginDialog({
    super.key,
    required this.lineId,
    required this.denial,
    required this.fetchStatus,
    required this.resubmit,
    this.backoff,
  });

  @override
  State<BiometricLoginDialog> createState() => _BiometricLoginDialogState();
}

class _BiometricLoginDialogState extends State<BiometricLoginDialog>
    with WidgetsBindingObserver {
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);

  late final BiometricLoginController _controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = BiometricLoginController(
      denial: widget.denial,
      fetchStatus: widget.fetchStatus,
      resubmit: widget.resubmit,
      backoff: widget.backoff,
    )..addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.onAppResumed();
  }

  void _onControllerChanged() {
    if (_controller.phase.isTerminal) _scheduleClose();
  }

  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) closeOwnRoute(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final loginStillNeeded =
        provider.isLineRendered(widget.lineId) &&
        provider.getUiState(widget.lineId) == LineUiState.needsPalletizerAuth;
    // A re-submitted login in flight decides for itself: its success is
    // exactly what makes the line leave the PIN state.
    if (!loginStillNeeded &&
        _controller.phase != BiometricLoginPhase.verifying &&
        !_controller.phase.isTerminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.cancel();
      });
    }
    final accent =
        provider.getLine(widget.lineId)?.color ??
        LineAccent.palette.first.color;
    final lineLabel = provider.lineLabel(widget.lineId);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _controller.canCancel) _controller.cancel();
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            scrollable: true,
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: _Header(
              visual: _visualFor(_controller.phase, accent),
              lineLabel: lineLabel,
              accent: accent,
            ),
            content: _body(),
            actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            actions: [_actions(accent)],
          ),
        ),
      ),
    );
  }

  _Visual _visualFor(BiometricLoginPhase phase, Color accent) {
    switch (phase) {
      case BiometricLoginPhase.deviceOffline:
      case BiometricLoginPhase.retry:
        return _Visual(
          phase == BiometricLoginPhase.retry
              ? Icons.timer_off_outlined
              : Icons.sensors_off_outlined,
          _amberDark,
          _amberLight,
        );
      case BiometricLoginPhase.network:
        return _Visual(
          Icons.wifi_off_rounded,
          Colors.grey.shade700,
          Colors.grey.shade200,
        );
      case BiometricLoginPhase.contactAdmin:
      case BiometricLoginPhase.failed:
        return _Visual(
          Icons.admin_panel_settings_outlined,
          Colors.red.shade700,
          Colors.red.shade50,
        );
      case BiometricLoginPhase.verifying:
      case BiometricLoginPhase.success:
        return _Visual(
          Icons.verified_user_outlined,
          Colors.green.shade700,
          Colors.green.shade50,
        );
      case BiometricLoginPhase.waiting:
      case BiometricLoginPhase.cancelled:
        return _Visual(
          Icons.fingerprint,
          accent,
          accent.withValues(alpha: 0.1),
        );
    }
  }

  Widget _body() {
    final message = _controller.message;
    String headline;
    String? detail;
    String? progress;
    switch (_controller.phase) {
      case BiometricLoginPhase.waiting:
      case BiometricLoginPhase.cancelled:
        headline = BiometricLoginStrings.waiting;
        detail = message;
        progress = BiometricLoginStrings.waitingSecondary;
      case BiometricLoginPhase.deviceOffline:
        headline = message ?? BiometricLoginStrings.deviceOffline;
        progress = BiometricLoginStrings.waitingSecondary;
      case BiometricLoginPhase.verifying:
      case BiometricLoginPhase.success:
        headline = BiometricLoginStrings.verifying;
        progress = '';
      case BiometricLoginPhase.retry:
        headline = message ?? BiometricLoginStrings.retry;
      case BiometricLoginPhase.network:
        headline = BiometricLoginStrings.network;
        progress = '';
      case BiometricLoginPhase.contactAdmin:
      case BiometricLoginPhase.failed:
        headline = message ?? BiometricLoginStrings.serverMappingMissing;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 18,
            height: 1.6,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade900,
          ),
        ),
        if (detail != null && detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey.shade700,
            ),
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              if (progress.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    progress,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _actions(Color accent) {
    final phase = _controller.phase;
    final buttons = <Widget>[
      if (phase == BiometricLoginPhase.retry)
        _PrimaryButton(
          label: BiometricLoginStrings.retryAction,
          color: accent,
          onPressed: _controller.retry,
        ),
      if (phase == BiometricLoginPhase.contactAdmin)
        _PrimaryButton(
          label: BiometricLoginStrings.okAction,
          color: accent,
          onPressed: _controller.cancel,
        ),
      if (_controller.canCancel)
        OutlinedButton(
          onPressed: _controller.cancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
            side: BorderSide(color: Colors.grey.shade400, width: 1.4),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            BiometricLoginStrings.cancelAction,
            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }
}

class _Visual {
  final IconData icon;
  final Color color;
  final Color background;

  const _Visual(this.icon, this.color, this.background);
}

class _Header extends StatelessWidget {
  final _Visual visual;
  final String lineLabel;
  final Color accent;

  const _Header({
    required this.visual,
    required this.lineLabel,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: visual.background,
            shape: BoxShape.circle,
          ),
          child: Icon(visual.icon, color: visual.color, size: 46),
        ),
        const SizedBox(height: 14),
        Text(
          BiometricLoginStrings.dialogTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        // Which line this login is for — several panes may be on screen.
        Text(
          lineLabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }
}
