import '../../domain/entities/bootstrap_response.dart';
import 'operator_model.dart';
import 'product_type_model.dart';
import 'production_line_model.dart';
import 'session_table_row_model.dart';
import 'line_handover_info_model.dart';

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
    super.pendingHandover,
    super.blockedReason,
    super.selectedProductType,
    super.currentProductTypeId,
    super.currentProductTypeName,
    super.lineUiMode,
    super.canInitiateHandover,
    super.canConfirmHandover,
    super.canRejectHandover,
    super.hasOpenFalet,
    super.openFaletCount,
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
    final handoverJson = json['pendingHandover'] as Map<String, dynamic>?;
    final selectedProductJson =
        json['selectedProductType'] as Map<String, dynamic>?;

    // New server-authoritative current product fields
    final currentProductTypeId = json['currentProductTypeId'] as int?;
    final currentProductTypeName = json['currentProductTypeName'] as String?;

    // Resolve selectedProductType: prefer full object from JSON, fall back
    // to constructing a minimal ProductType from the new id/name fields.
    ProductTypeModel? resolvedSelectedProduct;
    if (selectedProductJson != null) {
      resolvedSelectedProduct = ProductTypeModel.fromJson(selectedProductJson);
    } else if (currentProductTypeId != null && currentProductTypeName != null) {
      resolvedSelectedProduct = ProductTypeModel.minimal(
        id: currentProductTypeId,
        name: currentProductTypeName,
      );
    }

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
      pendingHandover: handoverJson != null
          ? LineHandoverInfoModel.fromJson(handoverJson)
          : null,
      blockedReason: json['blockedReason'] as String?,
      selectedProductType: resolvedSelectedProduct,
      currentProductTypeId: currentProductTypeId,
      currentProductTypeName: currentProductTypeName,
      lineUiMode: json['lineUiMode'] as String?,
      canInitiateHandover: json['canInitiateHandover'] as bool? ?? false,
      canConfirmHandover: json['canConfirmHandover'] as bool? ?? false,
      canRejectHandover: json['canRejectHandover'] as bool? ?? false,
      hasOpenFalet: json['hasOpenFalet'] as bool? ?? false,
      openFaletCount: json['openFaletCount'] as int? ?? 0,
    );
  }
}
