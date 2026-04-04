import 'pallet_create_response.dart';

class ProducePalletFromLooseResponse {
  final PalletCreateResponse pallet;
  final String creationMode;
  final int looseQuantityUsed;
  final int freshQuantityAdded;
  final int finalQuantity;

  const ProducePalletFromLooseResponse({
    required this.pallet,
    required this.creationMode,
    required this.looseQuantityUsed,
    required this.freshQuantityAdded,
    required this.finalQuantity,
  });
}
