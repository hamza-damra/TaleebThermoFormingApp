import '../../domain/entities/line_summary.dart';

class LineSummaryModel extends LineSummary {
  const LineSummaryModel({
    required super.lineId,
    required super.lineName,
    required super.lineNumber,
    required super.todayPalletCount,
    super.lastPalletAt,
    super.lastPalletAtDisplay,
  });

  factory LineSummaryModel.fromJson(Map<String, dynamic> json) {
    return LineSummaryModel(
      lineId: json['lineId'] as int,
      lineName: json['lineName'] as String,
      lineNumber: json['lineNumber'] as int,
      todayPalletCount: json['todayPalletCount'] as int,
      lastPalletAt: json['lastPalletAt'] != null
          ? DateTime.parse(json['lastPalletAt'] as String)
          : null,
      lastPalletAtDisplay: json['lastPalletAtDisplay'] as String?,
    );
  }
}
