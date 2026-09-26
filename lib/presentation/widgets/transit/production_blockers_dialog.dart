import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/production_transit_strings.dart';
import '../../../core/theme.dart';
import '../../../domain/entities/production_transit.dart';
import '../../providers/palletizing_provider.dart';
import '../../screens/transit_scan_screen.dart';
import '../line_scoped_route.dart';
import 'transit_ui.dart';

/// Which refused request the blocking dialog belongs to.
enum ProductionBlockerKind {
  /// `PREVIOUS_PALLET_STILL_AT_PRODUCTION` — blocks a pallet of the same
  /// product on the same shift-line.
  create,

  /// `PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS` — every pallet of the
  /// line at PRODUCTION blocks.
  logout,
}

enum _RowStatus { pending, verifying, moved, leftProduction }

/// The create-blocked and logout-blocked dialogs: the refusal text, the
/// blocking pallets and, per pallet, «نقل إلى الرصيف» — which opens the
/// scanner for THAT pallet; the move happens only after a fresh scan or a
/// typed number matching it.
///
/// Every row status and the registration action come from the backend's
/// pending list (re-read on open, after every move and on every SSE frame),
/// never from local flags: the action re-sends the refused request only
/// once a read confirms nothing on the line blocks any more.
class ProductionBlockersDialog extends StatefulWidget {
  final int lineId;
  final ProductionBlockerKind kind;
  final ProductionPalletBlockers blockers;

  const ProductionBlockersDialog({
    super.key,
    required this.lineId,
    required this.kind,
    required this.blockers,
  });

  /// `true` when the worker chose to re-send the refused request.
  static Future<bool> show(
    BuildContext context, {
    required int lineId,
    required ProductionBlockerKind kind,
    required ProductionPalletBlockers blockers,
  }) async {
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LineScopedRoute(
        lineId: lineId,
        child: ProductionBlockersDialog(
          lineId: lineId,
          kind: kind,
          blockers: blockers,
        ),
      ),
    );
    return retry == true;
  }

  @override
  State<ProductionBlockersDialog> createState() =>
      _ProductionBlockersDialogState();
}

class _ProductionBlockersDialogState extends State<ProductionBlockersDialog> {
  /// Last move outcome per pallet number — wording only, never readiness.
  final Map<String, TransitMoveOutcome> _outcomes = {};

  /// Pallets whose move the backend confirmed, awaiting the re-read.
  final Set<String> _verifying = {};
  bool _checking = false;

  /// A pending read completed after this dialog opened.
  bool _checkedSinceOpen = false;

  String get _message => widget.kind == ProductionBlockerKind.create
      ? ProductionTransitStrings.createBlocked
      : ProductionTransitStrings.logoutBlocked;

  String get _retryLabel => widget.kind == ProductionBlockerKind.create
      ? ProductionTransitStrings.createRetry
      : ProductionTransitStrings.logoutRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await context.read<PalletizingProvider>().refreshProductionPending();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkedSinceOpen = true;
    });
  }

  /// Opens the scanner for [pallet]; nothing is sent until the worker scans
  /// or types a matching identifier there.
  Future<void> _scan(ProductionPendingPallet pallet) async {
    final key = pallet.scannedValue;
    final outcome = await TransitScanScreen.scanSelected(
      context,
      pallet: pallet,
      lineId: widget.lineId,
    );
    if (!mounted || outcome == null) return;
    setState(() {
      _outcomes[key] = outcome;
      if (outcome.palletLeftProduction) _verifying.add(key);
    });
    await _check();
    if (!mounted) return;
    setState(() => _verifying.remove(key));
  }

  bool _blocks(ProductionPendingPallet pallet) {
    if (widget.kind == ProductionBlockerKind.logout) return true;
    // The backend's continuation rule: same product, same shift-line.
    final product = widget.blockers.productTypeId;
    final shiftLine =
        widget.blockers.lines.firstOrNull?.thermoformingShiftLineId;
    return (product == null || pallet.productTypeId == product) &&
        (shiftLine == null || pallet.thermoformingShiftLineId == shiftLine);
  }

  /// The line's blocking pallets per the backend's latest read, or `null`
  /// while that is not known (not read yet since opening, read failed, or no
  /// session covers the line).
  List<ProductionPendingPallet>? _stillBlocking(PalletizingProvider p) {
    if (!_checkedSinceOpen || !p.isProductionPendingConfirmed) return null;
    final line = p.productionPendingLine(widget.lineId);
    if (line == null) return null;
    return line.pallets.where(_blocks).toList();
  }

  _RowStatus _statusOf(
    ProductionPendingPallet pallet,
    List<ProductionPendingPallet>? blocking,
  ) {
    final key = pallet.scannedValue;
    if (_verifying.contains(key)) return _RowStatus.verifying;
    if (blocking == null || blocking.any((p) => p.scannedValue == key)) {
      return _RowStatus.pending;
    }
    final outcome = _outcomes[key];
    final movedHere =
        outcome != null &&
        (outcome.status == TransitMoveStatus.moved ||
            outcome.currentLocation == 'TRANSIT');
    return movedHere ? _RowStatus.moved : _RowStatus.leftProduction;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PalletizingProvider>();
    final blocking = _stillBlocking(provider);
    final busy = provider.isTransitMoveInFlight || _verifying.isNotEmpty;

    // The refused request's pallets, then any other blocker the backend
    // reports now (e.g. beyond the 50 listed in the refusal).
    final rows = <ProductionPendingPallet>[];
    final seen = <String>{};
    for (final pallet in [...widget.blockers.pallets, ...?blocking]) {
      if (seen.add(pallet.scannedValue)) rows.add(pallet);
    }
    final ready = blocking != null && blocking.isEmpty && !busy && !_checking;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: AppTheme.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(blocking),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                key: const Key('productionBlockersList'),
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _buildRow(rows[i], _statusOf(rows[i], blocking), busy),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(ready),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<ProductionPendingPallet>? blocking) {
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.warningColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _message,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStatus(blocking),
        ],
      ),
    );
  }

  Widget _buildStatus(List<ProductionPendingPallet>? blocking) {
    if (blocking == null) {
      if (_checking || !_checkedSinceOpen) {
        return _statusLine(
          key: const Key('productionBlockersChecking'),
          leading: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
          text: ProductionTransitStrings.checkingStatus,
          color: Colors.grey.shade700,
        );
      }
      return Row(
        key: const Key('productionBlockersCheckFailed'),
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: AppTheme.errorColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              ProductionTransitStrings.checkFailed,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppTheme.errorColor,
              ),
            ),
          ),
          TextButton(
            onPressed: _check,
            child: Text(
              ProductionTransitStrings.checkAgain,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }
    if (blocking.isEmpty) {
      return _statusLine(
        key: const Key('productionBlockersAllResolved'),
        leading: const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: AppTheme.successColor,
        ),
        text: ProductionTransitStrings.allResolved,
        color: AppTheme.successColor,
      );
    }
    return Row(
      children: [
        TransitStatusPill(
          key: const Key('productionBlockersRemaining'),
          text:
              '${ProductionTransitStrings.remainingLabel}: ${blocking.length}',
          icon: Icons.inventory_2_outlined,
          color: AppTheme.warningColor,
          fontSize: 13,
        ),
        if (_checking) ...[
          const SizedBox(width: 10),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusLine({
    required Key key,
    required Widget leading,
    required String text,
    required Color color,
  }) {
    return Row(
      key: key,
      children: [
        leading,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    ProductionPendingPallet pallet,
    _RowStatus status,
    bool busy,
  ) {
    final key = pallet.scannedValue;
    final Widget trailing = switch (status) {
      _RowStatus.pending => ElevatedButton.icon(
        key: ValueKey('blocker-move-$key'),
        onPressed: busy ? null : () => _scan(pallet),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            ProductionTransitStrings.action,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
      _RowStatus.verifying => Row(
        key: ValueKey('blocker-verifying-$key'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              ProductionTransitStrings.verifying,
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
      _RowStatus.moved => TransitStatusPill(
        key: ValueKey('blocker-moved-$key'),
        text: ProductionTransitStrings.moved,
        icon: Icons.check_circle_rounded,
        color: AppTheme.successColor,
      ),
      _RowStatus.leftProduction => TransitStatusPill(
        key: ValueKey('blocker-left-$key'),
        text: ProductionTransitStrings.leftProduction,
        icon: Icons.info_outline_rounded,
        color: Colors.grey.shade700,
        fontSize: 11,
      ),
    };

    // The last attempt's refusal while the pallet still blocks.
    final outcome = _outcomes[key];
    final failure =
        status == _RowStatus.pending &&
            outcome != null &&
            !outcome.palletLeftProduction
        ? (outcome.needsNewScan
              ? '${outcome.message}. ${ProductionTransitStrings.requestVoidedScanAgain}'
              : outcome.message)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PendingPalletTile(
          pallet: pallet,
          trailing: trailing,
          resolved:
              status == _RowStatus.moved || status == _RowStatus.leftProduction,
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              failure,
              key: ValueKey('blocker-failure-$key'),
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                color: AppTheme.errorColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(bool ready) {
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          TextButton(
            key: const Key('productionBlockersCloseButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              ProductionTransitStrings.close,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              key: const Key('productionBlockersRetryButton'),
              onPressed: ready ? () => Navigator.of(context).pop(true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _retryLabel,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
