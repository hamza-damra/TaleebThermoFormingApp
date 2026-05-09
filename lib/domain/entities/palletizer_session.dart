class PalletizerSession {
  final int sessionId;
  final int palletizerOperatorId;
  final String palletizerName;
  final int palletizingLineId;
  final String palletizingLineName;
  final int? thermoformingShiftId;
  final int? thermoformingShiftLineId;
  final String status;
  final DateTime? startedAt;
  final String? startedAtDisplay;
  final DateTime? lastUsedAt;
  final String? lastUsedAtDisplay;

  const PalletizerSession({
    required this.sessionId,
    required this.palletizerOperatorId,
    required this.palletizerName,
    required this.palletizingLineId,
    required this.palletizingLineName,
    this.thermoformingShiftId,
    this.thermoformingShiftLineId,
    this.status = 'ACTIVE',
    this.startedAt,
    this.startedAtDisplay,
    this.lastUsedAt,
    this.lastUsedAtDisplay,
  });

  bool get isActive => status == 'ACTIVE';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PalletizerSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
