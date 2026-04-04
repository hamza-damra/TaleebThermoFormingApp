import 'pallet_create_response.dart';

class CompleteIncompletePalletResponse {
  final PalletCreateResponse pallet;
  final String creationMode;
  final int incompleteQuantityUsed;
  final int freshQuantityAdded;
  final int finalQuantity;
  final int sourceHandoverId;

  const CompleteIncompletePalletResponse({
    required this.pallet,
    required this.creationMode,
    required this.incompleteQuantityUsed,
    required this.freshQuantityAdded,
    required this.finalQuantity,
    required this.sourceHandoverId,
  });
}
