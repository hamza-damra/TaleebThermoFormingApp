class LineSummary {
  final int lineId;
  final String lineName;
  final int lineNumber;
  final int todayPalletCount;
  final DateTime? lastPalletAt;
  final String? lastPalletAtDisplay;

  const LineSummary({
    required this.lineId,
    required this.lineName,
    required this.lineNumber,
    required this.todayPalletCount,
    this.lastPalletAt,
    this.lastPalletAtDisplay,
  });
}
