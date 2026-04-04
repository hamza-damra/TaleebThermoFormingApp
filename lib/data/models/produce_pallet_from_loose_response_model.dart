import '../../domain/entities/produce_pallet_from_loose_response.dart';
import 'pallet_create_response_model.dart';

class ProducePalletFromLooseResponseModel
    extends ProducePalletFromLooseResponse {
  const ProducePalletFromLooseResponseModel({
    required super.pallet,
    required super.creationMode,
    required super.looseQuantityUsed,
    required super.freshQuantityAdded,
    required super.finalQuantity,
  });

  factory ProducePalletFromLooseResponseModel.fromJson(
      Map<String, dynamic> json) {
    return ProducePalletFromLooseResponseModel(
      pallet: PalletCreateResponseModel.fromJson(
          json['pallet'] as Map<String, dynamic>),
      creationMode: json['creationMode'] as String,
      looseQuantityUsed: json['looseQuantityUsed'] as int,
      freshQuantityAdded: json['freshQuantityAdded'] as int,
      finalQuantity: json['finalQuantity'] as int,
    );
  }
}
