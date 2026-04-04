import '../../domain/entities/complete_incomplete_pallet_response.dart';
import 'pallet_create_response_model.dart';

class CompleteIncompletePalletResponseModel
    extends CompleteIncompletePalletResponse {
  const CompleteIncompletePalletResponseModel({
    required super.pallet,
    required super.creationMode,
    required super.incompleteQuantityUsed,
    required super.freshQuantityAdded,
    required super.finalQuantity,
    required super.sourceHandoverId,
  });

  factory CompleteIncompletePalletResponseModel.fromJson(
      Map<String, dynamic> json) {
    return CompleteIncompletePalletResponseModel(
      pallet: PalletCreateResponseModel.fromJson(
          json['pallet'] as Map<String, dynamic>),
      creationMode: json['creationMode'] as String,
      incompleteQuantityUsed: json['incompleteQuantityUsed'] as int,
      freshQuantityAdded: json['freshQuantityAdded'] as int,
      finalQuantity: json['finalQuantity'] as int,
      sourceHandoverId: json['sourceHandoverId'] as int,
    );
  }
}
