import '../../domain/entities/shift_info.dart';

class ShiftInfoModel extends ShiftInfo {
  const ShiftInfoModel({
    required super.shiftType,
    required super.shiftDisplayNameAr,
    required super.shiftDisplayNameEn,
    required super.profileType,
    required super.profileDisplayNameAr,
    required super.profileDisplayNameEn,
    required super.startTime,
    required super.endTime,
  });

  factory ShiftInfoModel.fromJson(Map<String, dynamic> json) {
    return ShiftInfoModel(
      shiftType: json['shiftType'] as String,
      shiftDisplayNameAr: json['shiftDisplayNameAr'] as String,
      shiftDisplayNameEn: json['shiftDisplayNameEn'] as String,
      profileType: json['profileType'] as String,
      profileDisplayNameAr: json['profileDisplayNameAr'] as String,
      profileDisplayNameEn: json['profileDisplayNameEn'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
    );
  }
}
