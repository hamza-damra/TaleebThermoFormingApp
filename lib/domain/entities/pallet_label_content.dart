import 'package:equatable/equatable.dart';

import 'pallet_create_response.dart';
import 'pallet_label.dart';
import 'palletizing_line.dart';
import 'product_type.dart';
import 'session_production_detail.dart';

/// Immutable business content for a physical pallet label.
///
/// This is the only object accepted by the label rendering/printing pipeline.
/// In particular, [actualQuantity] always comes from the individual pallet,
/// never from product-type defaults or display strings.
class PalletLabelContent extends Equatable {
  final int palletId;
  final String qrValue;
  final String productDisplayName;
  final int actualQuantity;
  final String? packageUnitDisplayName;
  final String lineDisplay;
  final int? sessionProductSequence;

  /// Grinding marker exactly as the backend decided it for this pallet — never
  /// computed from a grinding status here. Printed only through
  /// [grindingMarkerText].
  final bool grindingRecommended;
  final String? grindingLabelText;

  /// `false` once the pallet's grinding started or finished: no label may be
  /// printed for it any more. The printing pipeline refuses such content.
  final bool labelReprintAllowed;

  const PalletLabelContent({
    required this.palletId,
    required this.qrValue,
    required this.productDisplayName,
    required this.actualQuantity,
    required this.packageUnitDisplayName,
    required this.lineDisplay,
    this.sessionProductSequence,
    this.grindingRecommended = false,
    this.grindingLabelText,
    this.labelReprintAllowed = true,
  });

  String get productText => sessionProductSequence == null
      ? productDisplayName
      : '$productDisplayName ($sessionProductSequence)';

  String get actualQuantityText {
    final unit = packageUnitDisplayName?.trim();
    return unit == null || unit.isEmpty
        ? 'عدد العبوات: $actualQuantity'
        : 'عدد العبوات: $actualQuantity $unit';
  }

  String get sideText => '$qrValue ($lineDisplay)';

  /// The extra bottom line «(موصى بالجرش)», or `null` for a label without the
  /// marker. Present only when the backend flagged the pallet AND sent the
  /// text; an older backend sends neither, so its labels print as before.
  String? get grindingMarkerText {
    if (!grindingRecommended) return null;
    final text = grindingLabelText?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  List<Object?> get props => [
    palletId,
    qrValue,
    productDisplayName,
    actualQuantity,
    packageUnitDisplayName,
    lineDisplay,
    sessionProductSequence,
    grindingRecommended,
    grindingLabelText,
    labelReprintAllowed,
  ];
}

/// Authoritative mapping boundary between pallet DTOs and printable content.
class PalletLabelContentMapper {
  const PalletLabelContentMapper._();

  /// Canonical short indicator printed in the rotated side bands.
  ///
  /// Every print path resolves the side band through this helper so the same
  /// pallet reads identically whether it is printed on creation or reprinted
  /// later. Widgets must not spell `'A'` / `'B'` themselves.
  ///
  /// Derived from `lineNumber` (1 → A, 2 → B, 3 → C, …) — never from
  /// `lineId`, and never a two-way ternary.
  static String lineDisplayForNumber(int lineNumber) =>
      PalletizingLine.printLetterForNumber(lineNumber);

  static PalletLabelContent fromCreatedPallet(
    PalletCreateResponse pallet, {
    required int lineNumber,
  }) {
    return PalletLabelContent(
      palletId: pallet.palletId,
      qrValue: pallet.scannedValue,
      productDisplayName: pallet.productType.displayName,
      actualQuantity: pallet.quantity,
      packageUnitDisplayName: _nonBlank(
        pallet.productType.packageUnitDisplayName,
      ),
      lineDisplay: lineDisplayForNumber(lineNumber),
      sessionProductSequence: pallet.sessionProductSequence,
      grindingRecommended: pallet.grindingRecommended ?? false,
      grindingLabelText: _nonBlank(pallet.grindingLabelText),
      labelReprintAllowed: pallet.labelReprintAllowed ?? true,
    );
  }

  static PalletLabelContent fromSessionPallet({
    required SessionPalletDetail pallet,
    required SessionProductTypeGroup group,
    required ProductType? productType,
    required int lineNumber,
  }) {
    return PalletLabelContent(
      palletId: pallet.palletId,
      qrValue: pallet.scannedValue,
      productDisplayName: ProductType.resolveDisplayName(
        productType: productType,
        backendName: group.productTypeName,
      ),
      actualQuantity: pallet.quantity,
      packageUnitDisplayName: _nonBlank(productType?.packageUnitDisplayName),
      lineDisplay: lineDisplayForNumber(lineNumber),
      grindingRecommended: pallet.grindingRecommended ?? false,
      grindingLabelText: _nonBlank(pallet.grindingLabelText),
      labelReprintAllowed: pallet.labelReprintAllowed ?? true,
    );
  }

  /// [lineNumber] is the `lineNumber` of the line matching
  /// `label.productionLineId` (the label payload carries no line number).
  /// When it resolves, the side band carries the same letter the original
  /// print used; when the line is unknown the snapshot name on the pallet is
  /// the only remaining structured source, so it is used verbatim.
  static PalletLabelContent fromResolvedLabel(
    PalletLabel label, {
    ProductType? productType,
    int? lineNumber,
  }) {
    return PalletLabelContent(
      palletId: label.palletId,
      qrValue: label.scannedValue,
      productDisplayName: ProductType.resolveDisplayName(
        productType: productType,
        backendName: label.productTypeName,
      ),
      actualQuantity: label.quantity,
      packageUnitDisplayName:
          _nonBlank(label.packageUnitDisplayName) ??
          _nonBlank(productType?.packageUnitDisplayName),
      lineDisplay: lineNumber == null
          ? label.productionLineName
          : lineDisplayForNumber(lineNumber),
      grindingRecommended: label.grindingRecommended ?? false,
      grindingLabelText: _nonBlank(label.grindingLabelText),
      labelReprintAllowed: label.labelReprintAllowed ?? true,
    );
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
