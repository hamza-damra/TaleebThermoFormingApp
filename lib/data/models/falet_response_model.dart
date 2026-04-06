import '../../domain/entities/falet_response.dart';
import 'falet_item_model.dart';

class FaletResponseModel extends FaletResponse {
  const FaletResponseModel({
    required super.faletItems,
    required super.totalOpenFaletCount,
    required super.hasOpenFalet,
  });

  factory FaletResponseModel.fromJson(Map<String, dynamic> json) {
    final faletItemsJson = json['faletItems'] as List<dynamic>? ?? [];

    return FaletResponseModel(
      faletItems: faletItemsJson
          .map(
            (item) =>
                FaletItemModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      totalOpenFaletCount: json['totalOpenFaletCount'] as int? ?? 0,
      hasOpenFalet: json['hasOpenFalet'] as bool? ?? false,
    );
  }
}
