import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/constants/plan_item_close_request_strings.dart';
import '../../domain/entities/plan_item_close_request.dart';
import '../providers/palletizing_provider.dart';

/// Closes the route hosting [context] — and only that route — even when
/// another route (a notice, a nested dialog) is on top of it. A plain
/// `Navigator.pop` would close whatever is on top instead.
void closeOwnRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  final navigator = Navigator.of(context);
  if (route.isCurrent) {
    navigator.pop();
  } else {
    navigator.removeRoute(route);
  }
}

/// Blocking dialog for a close request in `WAITING_FOR_PALLETIZER_DECISION`
/// (handoff §7). The palletizer must pick one of the two answers: it cannot
/// be dismissed by tapping outside (shown with `barrierDismissible: false`)
/// or with the back button.
///
/// Bound to one [closeRequestId]. It closes itself as soon as the provider's
/// authoritative state no longer shows that request waiting on [lineId] — a
/// decision was applied, the operator cancelled, the request was invalidated,
/// or the session ended. The screen owns showing it, so a rebuild, a repeated
/// read or a duplicate SSE frame can never stack a second copy.
class PlanItemCloseRequestDialog extends StatefulWidget {
  final int lineId;
  final int closeRequestId;

  /// Called once "لا، بقيت طبليات للتسجيل" was applied, so the screen can
  /// bring the line (and its completing-pallets banner) into view.
  final VoidCallback? onMorePalletsRemain;

  const PlanItemCloseRequestDialog({
    super.key,
    required this.lineId,
    required this.closeRequestId,
    this.onMorePalletsRemain,
  });

  @override
  State<PlanItemCloseRequestDialog> createState() =>
      _PlanItemCloseRequestDialogState();
}

class _PlanItemCloseRequestDialogState
    extends State<PlanItemCloseRequestDialog> {
  static const Color _amberDark = Color(0xFFD97706);
  static const Color _amberLight = Color(0xFFFEF3C7);

  /// The request as last seen waiting — keeps the content on screen while
  /// the dialog animates out.
  PlanItemCloseRequest? _shown;
  bool _closing = false;

  /// Which answer is being submitted (`true` = all registered), for the
  /// spinner; both buttons are disabled from the provider's in-flight flag.
  bool? _submitting;

  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) closeOwnRoute(context);
    });
  }

  Future<void> _decide({required bool confirm}) async {
    final provider = context.read<PalletizingProvider>();
    if (_closing || provider.isCloseRequestDecisionInFlight(widget.lineId)) {
      return;
    }
    setState(() => _submitting = confirm);
    final outcome = confirm
        ? await provider.confirmAllPalletsRegistered(
            widget.lineId,
            widget.closeRequestId,
          )
        : await provider.reportMorePalletsRemain(
            widget.lineId,
            widget.closeRequestId,
          );
    if (!confirm && outcome == CloseDecisionOutcome.applied) {
      widget.onMorePalletsRemain?.call();
    }
    if (mounted) setState(() => _submitting = null);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final active = provider.getActiveCloseRequest(widget.lineId);
    final stillWaiting =
        active != null &&
        active.closeRequestId == widget.closeRequestId &&
        active.isWaitingForDecision;
    if (stillWaiting) {
      _shown = active;
    } else {
      _scheduleClose();
    }

    final request = _shown;
    final line = provider.getLine(widget.lineId);
    final accent = line?.color ?? LineAccent.palette.first.color;
    final inFlight = provider.isCloseRequestDecisionInFlight(widget.lineId);
    final error = provider.getCloseRequestDecisionError(widget.lineId);
    final enabled = stillWaiting && !inFlight;

    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _amberLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: _amberDark,
                  size: 42,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                PlanItemCloseRequestStrings.dialogTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                provider.lineLabel(widget.lineId),
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                PlanItemCloseRequestStrings.dialogBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 17,
                  height: 1.7,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
              if (request != null) ...[
                const SizedBox(height: 14),
                PlanItemCloseRequestContext(request: request),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                _DecisionError(message: error),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: enabled ? () => _decide(confirm: true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: accent.withValues(alpha: 0.45),
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(58),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _ButtonLabel(
                    label: PlanItemCloseRequestStrings.confirmAllAction,
                    loading: inFlight && _submitting == true,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: enabled ? () => _decide(confirm: false) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(
                      color: enabled ? accent : Colors.grey.shade400,
                      width: 1.6,
                    ),
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _ButtonLabel(
                    label: PlanItemCloseRequestStrings.morePalletsAction,
                    loading: inFlight && _submitting == false,
                    color: accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Short confirmation opened from the completing-pallets banner (handoff
/// §13). Stays open while the confirmation is in flight and shows the error
/// in place if it fails; closes itself once the request is no longer the
/// line's completing request (item closed, cancelled, invalidated).
class PlanItemCloseFinalConfirmDialog extends StatefulWidget {
  final int lineId;
  final int closeRequestId;

  const PlanItemCloseFinalConfirmDialog({
    super.key,
    required this.lineId,
    required this.closeRequestId,
  });

  @override
  State<PlanItemCloseFinalConfirmDialog> createState() =>
      _PlanItemCloseFinalConfirmDialogState();
}

class _PlanItemCloseFinalConfirmDialogState
    extends State<PlanItemCloseFinalConfirmDialog> {
  bool _closing = false;

  /// Only errors of a confirmation sent from THIS dialog are shown here.
  bool _submitted = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    closeOwnRoute(context);
  }

  void _scheduleClose() {
    if (_closing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _close();
    });
  }

  Future<void> _confirm() async {
    final provider = context.read<PalletizingProvider>();
    if (_closing || provider.isCloseRequestDecisionInFlight(widget.lineId)) {
      return;
    }
    setState(() => _submitted = true);
    await provider.confirmAllPalletsRegistered(
      widget.lineId,
      widget.closeRequestId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final active = provider.getActiveCloseRequest(widget.lineId);
    final stillCompleting =
        active != null &&
        active.closeRequestId == widget.closeRequestId &&
        active.isCompletingPallets;
    if (!stillCompleting) _scheduleClose();

    final line = provider.getLine(widget.lineId);
    final accent = line?.color ?? LineAccent.palette.first.color;
    final inFlight = provider.isCloseRequestDecisionInFlight(widget.lineId);
    final error = _submitted
        ? provider.getCloseRequestDecisionError(widget.lineId)
        : null;
    final enabled = stillCompleting && !inFlight;

    return PopScope(
      canPop: !inFlight,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            PlanItemCloseRequestStrings.finalConfirmTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                PlanItemCloseRequestStrings.finalConfirmBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  height: 1.7,
                  color: Colors.grey.shade900,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                _DecisionError(message: error),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: inFlight ? null : _close,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade800,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      PlanItemCloseRequestStrings.finalConfirmCancel,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: enabled ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: accent.withValues(alpha: 0.45),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _ButtonLabel(
                      label: PlanItemCloseRequestStrings.finalConfirmAction,
                      loading: inFlight,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Product and progress of the request — values from the backend response
/// only, never derived on the device.
class PlanItemCloseRequestContext extends StatelessWidget {
  final PlanItemCloseRequest request;

  const PlanItemCloseRequestContext({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final backendProduct = request.productTypeName;
    final product = backendProduct == null || backendProduct.trim().isEmpty
        ? null
        : context.watch<PalletizingProvider>().productDisplayName(
            productTypeId: request.productTypeId,
            backendName: backendProduct,
          );
    final requestedBy = request.requestedByOperatorName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product != null && product.trim().isNotEmpty)
            _ContextRow(
              label: PlanItemCloseRequestStrings.productLabel,
              value: product,
            ),
          _ContextRow(
            label: PlanItemCloseRequestStrings.producedLabel,
            value:
                '${request.producedPackageQuantity} / '
                '${request.targetPackageQuantity}',
          ),
          if (requestedBy != null && requestedBy.trim().isNotEmpty)
            _ContextRow(
              label: PlanItemCloseRequestStrings.requestedByLabel,
              value: requestedBy,
            ),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  final String label;
  final String value;

  const _ContextRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.cairo(color: Colors.grey.shade700),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
    );
  }
}

class _DecisionError extends StatelessWidget {
  final String message;

  const _DecisionError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  final String label;
  final bool loading;
  final Color color;

  const _ButtonLabel({
    required this.label,
    required this.loading,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(color: color, strokeWidth: 2.5),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }
}
