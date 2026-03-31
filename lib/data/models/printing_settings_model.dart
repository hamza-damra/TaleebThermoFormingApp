import 'package:hive/hive.dart';

part 'printing_settings_model.g.dart';

@HiveType(typeId: 12)
class PrintingSettingsModel extends HiveObject {
  @HiveField(0)
  String? lastPrinterId;

  @HiveField(1)
  String? lastPresetId;

  @HiveField(2)
  int lastCopies;

  PrintingSettingsModel({
    this.lastPrinterId,
    this.lastPresetId,
    this.lastCopies = 1,
  });
}
