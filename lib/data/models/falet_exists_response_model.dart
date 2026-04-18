import '../../domain/entities/falet_exists_response.dart';

class FaletExistsResponseModel extends FaletExistsResponse {
  const FaletExistsResponseModel({
    required super.hasOpenFalet,
    required super.openFaletCount,
    required super.requiresAction,
    required super.lineId,
    super.sessionId,
  });

  factory FaletExistsResponseModel.fromJson(Map<String, dynamic> json) {
    return FaletExistsResponseModel(
      hasOpenFalet: json['hasOpenFalet'] as bool? ?? false,
      openFaletCount: json['openFaletCount'] as int? ?? 0,
      requiresAction: json['requiresAction'] as bool? ?? false,
      lineId: json['lineId'] as int,
      sessionId: json['sessionId'] as int?,
    );
  }
}
