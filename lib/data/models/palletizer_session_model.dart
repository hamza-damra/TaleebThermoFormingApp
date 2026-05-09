import '../../domain/entities/palletizer_auth_result.dart';
import '../../domain/entities/palletizer_session.dart';

class PalletizerSessionModel extends PalletizerSession {
  const PalletizerSessionModel({
    required super.sessionId,
    required super.palletizerOperatorId,
    required super.palletizerName,
    required super.palletizingLineId,
    required super.palletizingLineName,
    super.thermoformingShiftId,
    super.thermoformingShiftLineId,
    super.status,
    super.startedAt,
    super.startedAtDisplay,
    super.lastUsedAt,
    super.lastUsedAtDisplay,
  });

  factory PalletizerSessionModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return PalletizerSessionModel(
      sessionId: json['sessionId'] as int,
      palletizerOperatorId: json['palletizerOperatorId'] as int,
      palletizerName: json['palletizerName'] as String? ?? '',
      palletizingLineId: json['palletizingLineId'] as int,
      palletizingLineName: json['palletizingLineName'] as String? ?? '',
      thermoformingShiftId: json['thermoformingShiftId'] as int?,
      thermoformingShiftLineId: json['thermoformingShiftLineId'] as int?,
      status: json['status'] as String? ?? 'ACTIVE',
      startedAt: parseDate(json['startedAt']),
      startedAtDisplay: json['startedAtDisplay'] as String?,
      lastUsedAt: parseDate(json['lastUsedAt']),
      lastUsedAtDisplay: json['lastUsedAtDisplay'] as String?,
    );
  }
}

class PalletizerAuthResultModel extends PalletizerAuthResult {
  const PalletizerAuthResultModel({
    required super.session,
    required super.sessionToken,
  });

  factory PalletizerAuthResultModel.fromJson(Map<String, dynamic> json) {
    final token = json['sessionToken'] as String? ?? '';
    return PalletizerAuthResultModel(
      session: PalletizerSessionModel.fromJson(json),
      sessionToken: token,
    );
  }
}
