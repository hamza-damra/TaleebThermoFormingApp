import 'operator.dart';
import 'product_type.dart';
import 'production_line.dart';
import 'session_table_row.dart';
import 'line_handover_info.dart';

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
  final LineHandoverInfo? pendingHandover;
  final String? blockedReason;
  final ProductType? selectedProductType;
  final String? lineUiMode;
  final bool canInitiateHandover;
  final bool canConfirmHandover;
  final bool canRejectHandover;
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
    this.pendingHandover,
    this.blockedReason,
    this.selectedProductType,
    this.lineUiMode,
    this.canInitiateHandover = false,
    this.canConfirmHandover = false,
    this.canRejectHandover = false,
    this.hasOpenFalet = false,
    this.openFaletCount = 0,
  });
}
