/// Server-side label payload for any pallet, resolved by its printed 12-digit
/// number. Returned by `GET /palletizing-line/pallets/{scannedValue}/label`.
///
/// Unlike `PalletCreateResponse`, this DTO carries snapshot strings for the
/// product type and production line — not nested objects — so the label is
/// always printable even when the original product type or line row has been
/// deleted.
class PalletLabel {
  final int palletId;
  final String scannedValue;

  /// Nullable — absent when the product type row was deleted after production.
  final int? productTypeId;

  /// Always present (snapshot stored on the pallet row).
  final String productTypeName;

  /// Always present (snapshot stored on the pallet row).
  final String productTypePrefix;

  /// Nullable — absent when the product type row was deleted after production.
  final int? packageQuantity;

  /// Structured package unit for cold/historical reprints. These fields are
  /// additive and nullable for backward compatibility with older servers.
  final String? packageUnit;
  final String? packageUnitDisplayName;

  /// Current recorded quantity (may differ from `packageQuantity` after a
  /// warehouse adjustment).
  final int quantity;

  /// Nullable — absent when the production line row was deleted.
  final int? productionLineId;

  /// Always present (snapshot stored on the pallet row).
  final String productionLineName;

  /// Always present (snapshot stored on the pallet row).
  final String operatorName;

  /// Absolute UTC instant of creation, ISO-8601 with trailing `Z`.
  final DateTime createdAt;

  /// Pre-formatted Arabic short form in Asia/Hebron business time.
  /// Use this on the sticker so reprints read identically to originals.
  final String createdAtDisplay;

  /// Grinding label marker, decided by the backend from the pallet's grinding
  /// order. All three are absent on an older backend, which means "no marker,
  /// reprint allowed".
  final bool? grindingRecommended;
  final String? grindingLabelText;
  final bool? labelReprintAllowed;

  const PalletLabel({
    required this.palletId,
    required this.scannedValue,
    this.productTypeId,
    required this.productTypeName,
    required this.productTypePrefix,
    this.packageQuantity,
    this.packageUnit,
    this.packageUnitDisplayName,
    required this.quantity,
    this.productionLineId,
    required this.productionLineName,
    required this.operatorName,
    required this.createdAt,
    required this.createdAtDisplay,
    this.grindingRecommended,
    this.grindingLabelText,
    this.labelReprintAllowed,
  });
}
