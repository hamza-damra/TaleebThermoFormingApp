/// Result of consuming matching FALET as part of a first-pallet creation.
///
/// Returned by the backend in the `faletConsumption` block on a successful
/// `POST /palletizing-line/lines/{lineId}/pallets` when the request carried a
/// `firstPalletFaletConsumption` payload. Absent for any other create-pallet
/// request.
class FaletConsumption {
  /// The FALET row the backend deducted from.
  final int consumedFaletId;

  /// Exact packages deducted in the same transaction as pallet creation.
  /// May be less than the requested `expectedFaletQuantity` if the backend
  /// saturated; the frontend treats this as the authoritative number.
  final int consumedQuantity;

  /// `RESOLVED` when the FALET row is now fully consumed (terminal), or
  /// `PARTIAL` when remaining quantity stays open. Other backend-defined
  /// values are tolerated and surface verbatim for debugging.
  final String faletStatusAfter;

  const FaletConsumption({
    required this.consumedFaletId,
    required this.consumedQuantity,
    required this.faletStatusAfter,
  });

  bool get isResolved => faletStatusAfter.toUpperCase() == 'RESOLVED';
}
