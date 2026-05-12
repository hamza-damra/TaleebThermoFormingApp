import 'operator.dart';
import 'product_type.dart';
import 'production_line.dart';
import 'session_table_row.dart';

class BootstrapResponse {
  final List<ProductType> productTypes;
  final List<ProductionLine> productionLines;
  final List<BootstrapLineState> lines;

  const BootstrapResponse({
    required this.productTypes,
    required this.productionLines,
    required this.lines,
  });
}

class BootstrapLineState {
  final int lineId;
  final int lineNumber;
  final String lineName;
  final bool isAuthorized;
  final Operator? authorizedOperator;
  final DateTime? authorizedAt;
  final List<SessionTableRow> sessionTable;
  final String? blockedReason;
  final ProductType? selectedProductType;
  final int? currentProductTypeId;
  final String? currentProductTypeName;
  final String? lineUiMode;
  final bool hasOpenFalet;
  final int openFaletCount;

  const BootstrapLineState({
    required this.lineId,
    required this.lineNumber,
    required this.lineName,
    this.isAuthorized = false,
    this.authorizedOperator,
    this.authorizedAt,
    this.sessionTable = const [],
    this.blockedReason,
    this.selectedProductType,
    this.currentProductTypeId,
    this.currentProductTypeName,
    this.lineUiMode,
    this.hasOpenFalet = false,
    this.openFaletCount = 0,
  });
}
