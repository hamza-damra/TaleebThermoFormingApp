/// Represents the last-active-product FALET that the operator is declaring
/// as part of handover creation.
///
/// If this product type already has an existing open FALET on the line from
/// the same authorization session, the backend will MERGE the quantities.
/// In that case [mergesWithFaletId] is set to the existing FALET's ID.
///
/// If no existing FALET matches, the backend creates a brand-new FALET
/// during handover processing. The frontend cannot know the new faletId,
/// so the resolution for this item is implicitly CARRY_FORWARD (handled
/// by the backend automatically).
class PendingLastActiveFalet {
  final int productTypeId;
  final String productTypeName;
  final int quantity;

  /// When non-null, the last-active FALET will merge into this existing FALET.
  /// The operator's resolution for that faletId covers the merged quantity.
  final int? mergesWithFaletId;

  const PendingLastActiveFalet({
    required this.productTypeId,
    required this.productTypeName,
    required this.quantity,
    this.mergesWithFaletId,
  });

  /// Whether this pending FALET will merge into an existing one.
  bool get willMerge => mergesWithFaletId != null;
}
