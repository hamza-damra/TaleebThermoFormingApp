import '../../domain/entities/falet_convert_to_pallet_response.dart';
import 'pallet_create_response_model.dart';

class FaletConvertToPalletResponseModel extends FaletConvertToPalletResponse {
  const FaletConvertToPalletResponseModel({
    required super.pallet,
    required super.creationMode,
    required super.faletQuantityUsed,
    required super.freshQuantityAdded,
    required super.finalQuantity,
    required super.faletId,
  });

  factory FaletConvertToPalletResponseModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return FaletConvertToPalletResponseModel(
      pallet: PalletCreateResponseModel.fromJson(
        json['pallet'] as Map<String, dynamic>,
      ),
      creationMode: json['creationMode'] as String,
      faletQuantityUsed: json['faletQuantityUsed'] as int,
      freshQuantityAdded: json['freshQuantityAdded'] as int,
      finalQuantity: json['finalQuantity'] as int,
      faletId: json['faletId'] as int,
    );
  }
}
