class ProductType {
  final int id;

  /// Backend `ProductType.name` — a **computed composite**, not a name:
  /// `productName / color / packageQuantity unit`
  /// (e.g. `TT-4 B600 Yellow / Yellow / 12 كيس`). Never render it directly;
  /// use [displayName].
  final String name;

  /// Structured product name (e.g. `TT-4 B600 Yellow`) — the canonical label.
  final String productName;
  final String prefix;
  final String color;
  final int packageQuantity;
  final String packageUnit;
  final String packageUnitDisplayName;
  final String displayLabel;
  final String? imageUrl;
  final String? description;

  ProductType({
    required this.id,
    required this.name,
    required this.productName,
    required this.prefix,
    required this.color,
    required this.packageQuantity,
    required this.packageUnit,
    required this.packageUnitDisplayName,
    String? displayLabel,
    this.imageUrl,
    this.description,
  }) : displayLabel =
           displayLabel ??
           '$productName - $color ($packageQuantity $packageUnitDisplayName)';

  /// The label every screen shows for this product: `TT-4 B600 Yellow`.
  String get displayName =>
      resolveDisplayName(productType: this, backendName: name);

  /// Canonical user-facing label for a product, from whatever the calling
  /// surface has.
  ///
  /// Every product string the backend sends the Palletizing App
  /// (`currentPlanItemProductName`, `productTypeName`, the per-pallet name
  /// snapshots) is the composite `ProductType.name`. Its structured
  /// `productName` already names the colour, so rendering the composite
  /// repeats it together with packaging metadata:
  /// `TT-4 B600 Yellow / Yellow / 12 كيس`.
  ///
  /// Resolution order:
  ///   1. [productType]'s structured `productName` — the bootstrap catalog
  ///      entry for the row's `productTypeId`, or the create-pallet response.
  ///   2. [backendName] with exactly the backend's composite suffix removed
  ///      ([productNameFromComposite]) — for a product the catalog does not
  ///      carry (deactivated since, or a historical reprint).
  ///   3. [backendName] verbatim.
  static String resolveDisplayName({
    ProductType? productType,
    String? backendName,
  }) {
    final structured = productType?.productName.trim();
    if (structured != null && structured.isNotEmpty) return structured;
    final raw = (backendName ?? productType?.name ?? '').trim();
    return productNameFromComposite(raw) ?? raw;
  }

  static const String _compositeSeparator = ' / ';

  /// `<packageQuantity> <unit>` — the last segment the backend appends
  /// (`12 كيس`, `32 كرتونة`). The unit is mandatory on the backend.
  static final RegExp _packageSegment = RegExp(r'^\d+ \S+$');

  /// Inverse of the backend's `ProductType.computeDisplayName()`
  /// (`productName + " / " + color + " / " + packageQuantity + " " + unit`).
  ///
  /// Removes exactly the two segments that method appends and only when the
  /// last one is a package segment, so everything the product name itself
  /// contains — `/`, ` / `, digits — is kept. Returns `null` when [value] does
  /// not end in that suffix (a plain or legacy name), in which case the caller
  /// keeps the value unchanged.
  static String? productNameFromComposite(String value) {
    final trimmed = value.trim();
    final packageAt = trimmed.lastIndexOf(_compositeSeparator);
    if (packageAt <= 0) return null;
    final packageSegment = trimmed.substring(
      packageAt + _compositeSeparator.length,
    );
    if (!_packageSegment.hasMatch(packageSegment.trim())) return null;

    final colorAt = trimmed
        .substring(0, packageAt)
        .lastIndexOf(_compositeSeparator);
    if (colorAt <= 0) return null;
    final productName = trimmed.substring(0, colorAt).trim();
    return productName.isEmpty ? null : productName;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductType &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
