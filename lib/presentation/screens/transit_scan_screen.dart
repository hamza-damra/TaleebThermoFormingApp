import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/constants/production_transit_strings.dart';
import '../../core/theme.dart';
import '../../domain/entities/production_transit.dart';
import '../providers/palletizing_provider.dart';
import '../widgets/transit/transit_ui.dart';

/// «نقل إلى الرصيف» — the one Scan action (V210). QR scan, or a typed
/// 12-digit number via «إدخال يدوي». No line, source, destination or product
/// is chosen: the backend resolves the pallet's line from the palletizer
/// session.
///
/// Opened from the top bar it stays open so pallets can be moved one after
/// another. Opened for a [selectedPallet] (a blocking-pallet card) it moves
/// only that pallet: the freshly scanned or typed identifier must match it —
/// the card's number is never sent on its own — and the screen closes with
/// the backend outcome once the pallet has left PRODUCTION.
class TransitScanScreen extends StatefulWidget {
  /// `false` starts (and stays) in manual entry — for platforms without the
  /// camera plugin, and for tests.
  final bool enableCamera;

  /// The only pallet this scan may move; `null` for the top-bar Scan.
  final ProductionPendingPallet? selectedPallet;

  /// Line whose palletizer token is tried first.
  final int? preferredLineId;

  TransitScanScreen({
    super.key,
    bool? enableCamera,
    this.selectedPallet,
    this.preferredLineId,
  }) : enableCamera =
           enableCamera ?? debugCameraEnabledOverride ?? cameraSupported;

  /// Platforms mobile_scanner supports.
  static bool get cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Forces manual entry in widget tests (no camera plugin there).
  @visibleForTesting
  static bool? debugCameraEnabledOverride;

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TransitScanScreen()));
  }

  /// Scans [pallet] and moves it when the identifier matches. Completes with
  /// the backend outcome of the last move attempt, or `null` when the worker
  /// closed the scanner before any request was sent.
  static Future<TransitMoveOutcome?> scanSelected(
    BuildContext context, {
    required ProductionPendingPallet pallet,
    int? lineId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<TransitMoveOutcome>(
        builder: (_) =>
            TransitScanScreen(selectedPallet: pallet, preferredLineId: lineId),
      ),
    );
  }

  @override
  State<TransitScanScreen> createState() => _TransitScanScreenState();
}

class _TransitScanScreenState extends State<TransitScanScreen> {
  final _numberController = TextEditingController();
  late bool _manual = !widget.enableCamera;
  String? _inputError;
  TransitMoveOutcome? _outcome;

  /// The last backend answer — handed back when the screen closes.
  TransitMoveOutcome? _lastOutcome;

  /// A camera read that is not the selected pallet (canonical value).
  String? _mismatch;

  /// The last submission — «إعادة المحاولة» resends it, and the provider
  /// reuses its `clientRequestId`.
  String? _lastIdentifier;
  PalletTransitScanType _lastScanType = PalletTransitScanType.qr;

  /// After a result the camera usually still sees the pallet just handled —
  /// ignore that code for a moment.
  String? _ignoredCanonical;
  DateTime? _ignoreUntil;

  bool get _selectedMode => widget.selectedPallet != null;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_manual || _outcome != null || _mismatch != null) return;
    final provider = context.read<PalletizingProvider>();
    if (provider.isTransitMoveInFlight) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere(
          (v) => v != null && v.trim().isNotEmpty,
          orElse: () => null,
        );
    if (raw == null) return;
    final until = _ignoreUntil;
    if (until != null &&
        DateTime.now().isBefore(until) &&
        PalletIdentifier.canonicalize(raw) == _ignoredCanonical) {
      return;
    }
    HapticFeedback.mediumImpact();
    _submit(raw, PalletTransitScanType.qr);
  }

  void _submitManual() {
    final text = _numberController.text;
    final canonical = PalletIdentifier.canonicalize(text);
    if (canonical.isEmpty) {
      setState(
        () => _inputError = ProductionTransitStrings.palletNumberRequired,
      );
      return;
    }
    if (!PalletIdentifier.isValid(text)) {
      setState(() => _inputError = ProductionTransitStrings.palletNumberLength);
      return;
    }
    _submit(text, PalletTransitScanType.number);
  }

  Future<void> _submit(String identifier, PalletTransitScanType type) async {
    final provider = context.read<PalletizingProvider>();
    final selected = widget.selectedPallet;
    final canonical = PalletIdentifier.canonicalize(identifier);
    // Only the selected pallet may be moved from here — a different pallet
    // is refused before anything is sent.
    if (selected != null &&
        canonical != PalletIdentifier.canonicalize(selected.scannedValue)) {
      HapticFeedback.heavyImpact();
      setState(() {
        if (type == PalletTransitScanType.number) {
          _inputError = ProductionTransitStrings.identifierMismatch;
        } else {
          _mismatch = canonical;
        }
      });
      return;
    }

    setState(() {
      _inputError = null;
      _lastIdentifier = identifier;
      _lastScanType = type;
    });
    final outcome = await provider.movePalletToTransit(
      identifier,
      scanType: type,
      preferredLineId: widget.preferredLineId,
    );
    if (!mounted) return;
    // A second frame while a move was in flight — the first one answers.
    if (outcome.status == TransitMoveStatus.ignored &&
        provider.canMoveToTransit) {
      return;
    }
    _lastOutcome = outcome;
    if (outcome.status == TransitMoveStatus.moved) {
      HapticFeedback.heavyImpact();
    }
    if (_selectedMode && outcome.palletLeftProduction) {
      Navigator.of(context).pop(outcome);
      return;
    }
    setState(() => _outcome = outcome);
  }

  void _retry() {
    final identifier = _lastIdentifier;
    if (identifier == null) return;
    setState(() => _outcome = null);
    _submit(identifier, _lastScanType);
  }

  /// Back to scanning. [ignoreLast] keeps the camera from re-reading the
  /// code just handled; a retry of the same pallet needs exactly that code.
  void _scanNext({bool ignoreLast = true}) {
    final last = _mismatch ?? _outcome?.scannedValue;
    setState(() {
      _outcome = null;
      _mismatch = null;
      _inputError = null;
      _numberController.clear();
      if (ignoreLast && last != null) {
        _ignoredCanonical = last;
        _ignoreUntil = DateTime.now().add(const Duration(seconds: 3));
      } else {
        _ignoredCanonical = null;
        _ignoreUntil = null;
      }
    });
  }

  void _close() => Navigator.of(context).pop(_lastOutcome);

  @override
  Widget build(BuildContext context) {
    final moving = context.select<PalletizingProvider, bool>(
      (p) => p.isTransitMoveInFlight,
    );
    final outcome = _outcome;
    final selected = widget.selectedPallet;

    return PopScope<TransitMoveOutcome>(
      canPop: false,
      // Back / close hands the last backend answer to the caller.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          leading: IconButton(
            key: const Key('transitScanCloseButton'),
            tooltip: ProductionTransitStrings.close,
            icon: const Icon(Icons.close_rounded),
            onPressed: _close,
          ),
          title: Text(
            selected == null
                ? ProductionTransitStrings.action
                : ProductionTransitStrings.scanSelectedTitle,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            if (selected != null) _SelectedPalletBanner(pallet: selected),
            Expanded(
              child: Stack(
                children: [
                  if (outcome != null)
                    _buildOutcome(outcome)
                  else if (_mismatch != null)
                    _buildMismatch(_mismatch!)
                  else if (_manual)
                    _buildManual(moving)
                  else
                    _buildCamera(),
                  if (moving) const _MovingOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return Stack(
      children: [
        // Owns its controller: starts on mount, stops on unmount and follows
        // the app lifecycle.
        MobileScanner(
          onDetect: _onDetect,
          errorBuilder: (context, error, _) => _buildCameraError(error),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ProductionTransitStrings.scanHint,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _manualEntryButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualEntryButton() {
    return ElevatedButton.icon(
      key: const Key('transitManualEntryButton'),
      onPressed: () => setState(() => _manual = true),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.keyboard_rounded),
      label: Text(
        ProductionTransitStrings.manualEntry,
        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final text = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? ProductionTransitStrings.cameraPermissionDenied
        : ProductionTransitStrings.cameraUnavailable;
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            _manualEntryButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildManual(bool moving) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.keyboard_rounded,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ProductionTransitStrings.manualEntry,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Never prefilled — the worker types the number printed on
                  // the pallet in front of them.
                  TextField(
                    key: const Key('transitNumberField'),
                    controller: _numberController,
                    autofocus: true,
                    enabled: !moving,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    style: GoogleFonts.robotoMono(fontSize: 18),
                    inputFormatters: [_PalletDigitsFormatter()],
                    decoration: InputDecoration(
                      labelText: ProductionTransitStrings.palletNumberLabel,
                      labelStyle: GoogleFonts.cairo(),
                      hintText: ProductionTransitStrings.palletNumberHint,
                      errorText: _inputError,
                      errorMaxLines: 3,
                      errorStyle: GoogleFonts.cairo(),
                      prefixIcon: const Icon(
                        Icons.qr_code_2_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) {
                      if (_inputError != null) {
                        setState(() => _inputError = null);
                      }
                    },
                    // A keyboard-wedge scanner types the number and Enter.
                    onSubmitted: (_) => _submitManual(),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    key: const Key('transitSubmitButton'),
                    onPressed: moving ? null : _submitManual,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.local_shipping_rounded),
                    label: Text(
                      ProductionTransitStrings.submit,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (widget.enableCamera) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: moving
                          ? null
                          : () => setState(() {
                              _manual = false;
                              _inputError = null;
                            }),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text(
                        ProductionTransitStrings.backToCamera,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A camera read of another pallet — nothing was sent.
  Widget _buildMismatch(String scanned) {
    return _centered(
      children: [
        Container(
          key: const Key('transitMismatchCard'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.errorColor.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: 8),
              Text(
                ProductionTransitStrings.identifierMismatch,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _numberRow(ProductionTransitStrings.scannedPalletLabel, scanned),
              _numberRow(
                ProductionTransitStrings.selectedPalletLabel,
                widget.selectedPallet!.scannedValue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          key: const Key('transitScanAgainButton'),
          icon: Icons.qr_code_scanner_rounded,
          label: ProductionTransitStrings.scanAgain,
          onPressed: _scanNext,
        ),
        const SizedBox(height: 10),
        _secondaryButton(
          key: const Key('transitMismatchManualButton'),
          icon: Icons.keyboard_rounded,
          label: ProductionTransitStrings.manualEntry,
          onPressed: () => setState(() {
            _mismatch = null;
            _manual = true;
          }),
        ),
      ],
    );
  }

  Widget _numberRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade700),
        ),
        Expanded(child: PalletNumberText(value, fontSize: 15)),
      ],
    );
  }

  Widget _buildOutcome(TransitMoveOutcome outcome) {
    final canScan = context.select<PalletizingProvider, bool>(
      (p) => p.canMoveToTransit,
    );
    final buttons = <Widget>[
      if (outcome.canRetry)
        _primaryButton(
          key: const Key('transitRetryButton'),
          icon: Icons.refresh_rounded,
          label: ProductionTransitStrings.retry,
          onPressed: _retry,
        ),
      if (canScan)
        if (_selectedMode || outcome.needsNewScan)
          (outcome.canRetry ? _secondaryButton : _primaryButton)(
            key: const Key('transitScanAgainButton'),
            icon: Icons.qr_code_scanner_rounded,
            label: ProductionTransitStrings.scanAgain,
            onPressed: () => _scanNext(ignoreLast: false),
          )
        else
          (outcome.canRetry ? _secondaryButton : _primaryButton)(
            key: const Key('transitScanNextButton'),
            icon: Icons.qr_code_scanner_rounded,
            label: ProductionTransitStrings.scanNext,
            onPressed: _scanNext,
          ),
      _secondaryButton(
        key: const Key('transitCloseButton'),
        icon: Icons.close_rounded,
        label: ProductionTransitStrings.close,
        onPressed: _close,
      ),
    ];
    return _centered(
      children: [
        TransitMoveResultCard(outcome: outcome),
        const SizedBox(height: 16),
        for (final button in buttons) ...[button, const SizedBox(height: 10)],
      ],
    );
  }

  Widget _centered({required List<Widget> children}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      key: key,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon),
      label: Text(
        label,
        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _secondaryButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon),
      label: Text(
        label,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }
}

/// Which pallet a blocking-card scan is for — the number the worker looks
/// for on the pallet. Never used as the request identifier.
class _SelectedPalletBanner extends StatelessWidget {
  final ProductionPendingPallet pallet;

  const _SelectedPalletBanner({required this.pallet});

  @override
  Widget build(BuildContext context) {
    final product = context.read<PalletizingProvider>().productDisplayName(
      productTypeId: pallet.productTypeId,
      backendName: pallet.productTypeName,
    );
    return Material(
      key: const Key('transitSelectedPalletBanner'),
      color: AppTheme.surfaceColor,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ProductionTransitStrings.scanSelectedHint,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${ProductionTransitStrings.selectedPalletLabel}: ',
                  style: GoogleFonts.cairo(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(child: PalletNumberText(pallet.scannedValue)),
              ],
            ),
            if (product.isNotEmpty)
              Text(
                product,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MovingOverlay extends StatelessWidget {
  const _MovingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 14),
              Text(
                ProductionTransitStrings.moving,
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps ASCII and Arabic-Indic digits only — the backend normalises the
/// Arabic-Indic ones — and at most [maxDigits]: an edit that would go past
/// it (a 13th digit, a longer paste) is refused and the field keeps its
/// previous value.
class _PalletDigitsFormatter extends TextInputFormatter {
  static const int maxDigits = 12;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = String.fromCharCodes(
      newValue.text.runes.where(PalletIdentifier.isDigitRune),
    );
    if (filtered.runes.length > maxDigits) return oldValue;
    if (filtered == newValue.text) return newValue;
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}
