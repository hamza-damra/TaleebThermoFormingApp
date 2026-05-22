import '../../domain/entities/bootstrap_response.dart';
import 'operator_model.dart';
import 'product_type_model.dart';
import 'production_line_model.dart';
import 'session_table_row_model.dart';
import 'takeover_request_model.dart';

class BootstrapResponseModel extends BootstrapResponse {
  const BootstrapResponseModel({
    required super.productTypes,
    required super.productionLines,
    required super.lines,
  });

  factory BootstrapResponseModel.fromJson(Map<String, dynamic> json) {
    final productTypesJson = json['productTypes'] as List<dynamic>? ?? [];
    final productionLinesJson = json['productionLines'] as List<dynamic>? ?? [];
    final linesJson = json['lines'] as List<dynamic>? ?? [];

    return BootstrapResponseModel(
      productTypes: productTypesJson
          .map(
            (item) => ProductTypeModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      productionLines: productionLinesJson
          .map(
            (item) =>
                ProductionLineModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      lines: linesJson
          .map(
            (item) =>
                BootstrapLineStateModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class BootstrapLineStateModel extends BootstrapLineState {
  const BootstrapLineStateModel({
    required super.lineId,
    required super.lineNumber,
    required super.lineName,
    super.isAuthorized,
    super.authorizedOperator,
    super.authorizedAt,
    super.sessionTable,
    super.blockedReason,
    super.lineUiMode,
    super.hasOpenFalet,
    super.openFaletCount,
    super.currentPlanItemId,
    super.currentPlanItemProductTypeId,
    super.currentPlanItemProductName,
    super.currentPlanItemPackagesPerPallet,
    super.defaultPackageQuantitySource,
    super.productionPlanBlocked,
    super.productionPlanBlockedReason,
    super.productionPlanBlockedMessage,
    super.waitingForOperator,
    super.waitingForOperatorReason,
    super.waitingForOperatorMessageTitle,
    super.waitingForOperatorMessage,
    super.takeoverRequestStatus,
    super.pendingTakeoverRequest,
    super.takeoverRemainingSeconds,
    super.takeoverHandoverRemainingSeconds,
    super.takeoverRequestedByOperatorName,
    super.takeoverCurrentOperatorName,
    super.blocked,
  });

  factory BootstrapLineStateModel.fromJson(Map<String, dynamic> json) {
    // Backend sends 'authorized' (not 'isAuthorized')
    final isAuthorized = json['authorized'] as bool? ?? false;

    // Backend nests operator info inside 'authorization' object
    final authorizationJson = json['authorization'] as Map<String, dynamic>?;
    OperatorModel? authorizedOperator;
    DateTime? authorizedAt;

    if (authorizationJson != null) {
      final operatorId = authorizationJson['operatorId'] as int?;
      final operatorName = authorizationJson['operatorName'] as String?;
      if (operatorId != null && operatorName != null) {
        authorizedOperator = OperatorModel(
          id: operatorId,
          name: operatorName,
          displayLabel: operatorName,
        );
      }
      final authorizedAtStr = authorizationJson['authorizedAt'] as String?;
      if (authorizedAtStr != null) {
        authorizedAt = DateTime.tryParse(authorizedAtStr);
      }
    }

    final sessionTableJson = json['sessionTable'] as List<dynamic>? ?? [];

    // Line Takeover Request (V75). All optional — absent on legacy responses.
    final pendingTakeoverJson =
        json['pendingTakeoverRequest'] as Map<String, dynamic>?;

    return BootstrapLineStateModel(
      lineId: json['lineId'] as int,
      lineNumber: json['lineNumber'] as int,
      lineName: json['lineName'] as String? ?? '',
      isAuthorized: isAuthorized,
      authorizedOperator: authorizedOperator,
      authorizedAt: authorizedAt,
      sessionTable: sessionTableJson
          .map(
            (item) =>
                SessionTableRowModel.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      blockedReason: json['blockedReason'] as String?,
      lineUiMode: json['lineUiMode'] as String?,
      hasOpenFalet: json['hasOpenFalet'] as bool? ?? false,
      openFaletCount: json['openFaletCount'] as int? ?? 0,
      // Thermoforming Production Plan (V79/V81). Absent when there is no
      // active plan item — JsonInclude(NON_NULL) on the backend omits the keys.
      currentPlanItemId: json['currentPlanItemId'] as int?,
      currentPlanItemProductTypeId:
          json['currentPlanItemProductTypeId'] as int?,
      currentPlanItemProductName:
          json['currentPlanItemProductName'] as String?,
      currentPlanItemPackagesPerPallet:
          json['currentPlanItemPackagesPerPallet'] as int?,
      defaultPackageQuantitySource:
          json['defaultPackageQuantitySource'] as String?,
      productionPlanBlocked:
          json['productionPlanBlocked'] as bool? ?? false,
      productionPlanBlockedReason:
          json['productionPlanBlockedReason'] as String?,
      productionPlanBlockedMessage:
          json['productionPlanBlockedMessage'] as String?,
      // Waiting-for-Operator (V81+, 2026-05-21). Absent on pre-V81+ responses
      // and on non-thermoforming-linked palletizing lines.
      waitingForOperator: json['waitingForOperator'] as bool? ?? false,
      waitingForOperatorReason: json['waitingForOperatorReason'] as String?,
      waitingForOperatorMessageTitle:
          json['waitingForOperatorMessageTitle'] as String?,
      waitingForOperatorMessage:
          json['waitingForOperatorMessage'] as String?,
      takeoverRequestStatus: json['takeoverRequestStatus'] as String?,
      pendingTakeoverRequest: pendingTakeoverJson != null
          ? TakeoverRequestModel.fromJson(pendingTakeoverJson)
          : null,
      takeoverRemainingSeconds: json['takeoverRemainingSeconds'] as int?,
      takeoverHandoverRemainingSeconds:
          json['takeoverHandoverRemainingSeconds'] as int?,
      takeoverRequestedByOperatorName:
          json['takeoverRequestedByOperatorName'] as String?,
      takeoverCurrentOperatorName:
          json['takeoverCurrentOperatorName'] as String?,
      blocked: json['blocked'] as bool? ?? false,
    );
  }
}
