import 'pallet_create_response.dart';

class FaletConvertToPalletResponse {
  final PalletCreateResponse pallet;
  final String creationMode;
  final int faletQuantityUsed;
  final int freshQuantityAdded;
  final int finalQuantity;
  final int faletId;

  const FaletConvertToPalletResponse({
    required this.pallet,
    required this.creationMode,
    required this.faletQuantityUsed,
    required this.freshQuantityAdded,
    required this.finalQuantity,
    required this.faletId,
  });
}
