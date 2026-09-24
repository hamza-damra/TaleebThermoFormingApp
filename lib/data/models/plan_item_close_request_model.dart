import '../../domain/entities/plan_item_close_request.dart';

class PlanItemCloseRequestModel extends PlanItemCloseRequest {
  const PlanItemCloseRequestModel({
    required super.closeRequestId,
    required super.status,
    required super.productionPlanItemId,
    required super.palletizingLineId,
    super.productTypeId,
    super.productTypeName,
    super.targetPackageQuantity,
    super.producedPackageQuantity,
    super.thermoformingLineId,
    super.requestedByOperatorName,
    super.requestedAt,
    super.morePalletsReportedAt,
    super.morePalletsReportedByName,
    super.confirmedAt,
    super.confirmedByPalletizerName,
    super.resultingNextItemId,
    super.invalidationReason,
    super.alreadyProcessed,
  });

  /// Parses `PalletizerPlanItemCloseRequestResponse`. Null fields are omitted
  /// on the wire. Throws [FormatException] when an id the app routes by is
  /// missing — a request that cannot be addressed must never be shown.
  factory PlanItemCloseRequestModel.fromJson(Map<String, dynamic> json) {
    return PlanItemCloseRequestModel(
      closeRequestId: _requiredInt(json, 'closeRequestId'),
      status: PlanItemCloseRequestStatus.fromString(json['status'] as String?),
      productionPlanItemId: _requiredInt(json, 'productionPlanItemId'),
      palletizingLineId: _requiredInt(json, 'palletizingLineId'),
      productTypeId: _asInt(json['productTypeId']),
      productTypeName: json['productTypeName'] as String?,
      targetPackageQuantity: _asInt(json['targetPackageQuantity']) ?? 0,
      producedPackageQuantity: _asInt(json['producedPackageQuantity']) ?? 0,
      thermoformingLineId: _asInt(json['thermoformingLineId']),
      requestedByOperatorName: json['requestedByOperatorName'] as String?,
      requestedAt: _asDate(json['requestedAt']),
      morePalletsReportedAt: _asDate(json['morePalletsReportedAt']),
      morePalletsReportedByName: json['morePalletsReportedByName'] as String?,
      confirmedAt: _asDate(json['confirmedAt']),
      confirmedByPalletizerName: json['confirmedByPalletizerName'] as String?,
      resultingNextItemId: _asInt(json['resultingNextItemId']),
      invalidationReason: json['invalidationReason'] as String?,
      alreadyProcessed: json['alreadyProcessed'] as bool? ?? false,
    );
  }

  /// Parses `PalletizerActivePlanItemCloseRequestResponse`. Returns `null`
  /// when `hasActiveRequest` is `false` (or the `request` object is absent).
  static PlanItemCloseRequest? activeFromJson(Map<String, dynamic> json) {
    if (json['hasActiveRequest'] != true) return null;
    final request = json['request'];
    if (request is! Map<String, dynamic>) return null;
    return PlanItemCloseRequestModel.fromJson(request);
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = _asInt(json[key]);
    if (value == null) {
      throw FormatException('plan-item close request is missing "$key"');
    }
    return value;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDate(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}
