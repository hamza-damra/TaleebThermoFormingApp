import '../../domain/entities/takeover_request.dart';
import '../../domain/entities/takeover_status.dart';

class TakeoverRequestModel extends TakeoverRequest {
  const TakeoverRequestModel({
    required super.id,
    required super.status,
    super.statusDisplayNameAr,
    super.requestedByOperatorName,
    super.currentOperatorName,
    super.requestedAt,
    super.expiresAt,
    super.remainingSeconds,
    super.handoverExpiresAt,
    super.handoverRemainingSeconds,
    super.autoRelease,
  });

  factory TakeoverRequestModel.fromJson(Map<String, dynamic> json) {
    return TakeoverRequestModel(
      // `id` may arrive as int or string — normalise to string so the
      // alert-dedupe key is uniform.
      id: json['id']?.toString() ?? '',
      status: TakeoverStatus.fromString(json['status'] as String?),
      statusDisplayNameAr: json['statusDisplayNameAr'] as String?,
      requestedByOperatorName: json['requestedByOperatorName'] as String?,
      currentOperatorName: json['currentOperatorName'] as String?,
      requestedAt: _parseDate(json['requestedAt']),
      expiresAt: _parseDate(json['expiresAt']),
      remainingSeconds: json['remainingSeconds'] as int?,
      handoverExpiresAt: _parseDate(json['handoverExpiresAt']),
      handoverRemainingSeconds: json['handoverRemainingSeconds'] as int?,
      autoRelease: json['autoRelease'] as bool? ?? false,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}
