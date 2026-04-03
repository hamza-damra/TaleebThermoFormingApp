class LineHandoverInfo {
  final int handoverId;
  final int lineId;
  final int lineNumber;
  final String? lineName;
  final String status;
  final String? statusDisplayNameAr;
  final String? handoverType; // NONE, INCOMPLETE_PALLET_ONLY, LOOSE_BALANCES_ONLY, BOTH
  final String? outgoingOperatorName;
  final int? outgoingOperatorId;
  final String? incomingOperatorName;
  final int? incomingOperatorId;
  final IncompletePalletInfo? incompletePallet;
  final List<LooseBalanceItem> looseBalances;
  final int looseBalanceCount;
  final bool hasIncompletePallet;
  final String? notes;
  final String? rejectionNotes;
  final String? resolutionNotes;
  final String? resolvedByUserName;
  final DateTime? createdAt;
  final String? createdAtDisplay;
  final String? confirmedAtDisplay;
  final String? rejectedAtDisplay;
  final String? resolvedAtDisplay;

  const LineHandoverInfo({
    required this.handoverId,
    required this.lineId,
    this.lineNumber = 0,
    this.lineName,
    required this.status,
    this.statusDisplayNameAr,
    this.handoverType,
    this.outgoingOperatorName,
    this.outgoingOperatorId,
    this.incomingOperatorName,
    this.incomingOperatorId,
    this.incompletePallet,
    this.looseBalances = const [],
    this.looseBalanceCount = 0,
    this.hasIncompletePallet = false,
    this.notes,
    this.rejectionNotes,
    this.resolutionNotes,
    this.resolvedByUserName,
    this.createdAt,
    this.createdAtDisplay,
    this.confirmedAtDisplay,
    this.rejectedAtDisplay,
    this.resolvedAtDisplay,
  });

  bool get isPending => status == 'PENDING';
}

class IncompletePalletInfo {
  final int? productTypeId;
  final String productTypeName;
  final int quantity;

  const IncompletePalletInfo({
    this.productTypeId,
    required this.productTypeName,
    required this.quantity,
  });
}

class LooseBalanceItem {
  final int productTypeId;
  final String productTypeName;
  final int loosePackageCount;

  const LooseBalanceItem({
    required this.productTypeId,
    required this.productTypeName,
    required this.loosePackageCount,
  });
}
