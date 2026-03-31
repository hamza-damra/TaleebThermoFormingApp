import '../entities/label_preset.dart';

abstract class PresetRepository {
  List<LabelPreset> getAll();
  LabelPreset? getById(String id);
  Future<void> save(LabelPreset preset);
  Future<void> delete(String id);
}
