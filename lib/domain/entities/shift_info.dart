class ShiftInfo {
  final String shiftType;
  final String shiftDisplayNameAr;
  final String shiftDisplayNameEn;
  final String profileType;
  final String profileDisplayNameAr;
  final String profileDisplayNameEn;
  final String startTime;
  final String endTime;

  const ShiftInfo({
    required this.shiftType,
    required this.shiftDisplayNameAr,
    required this.shiftDisplayNameEn,
    required this.profileType,
    required this.profileDisplayNameAr,
    required this.profileDisplayNameEn,
    required this.startTime,
    required this.endTime,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShiftInfo &&
          runtimeType == other.runtimeType &&
          shiftType == other.shiftType &&
          profileType == other.profileType;

  @override
  int get hashCode => shiftType.hashCode ^ profileType.hashCode;
}
