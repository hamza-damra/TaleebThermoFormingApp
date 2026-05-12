import '../entities/label_preset.dart';

abstract class PresetRepository {
  List<LabelPreset> getAll();
  LabelPreset? getById(String id);
  /// Persists [preset] and returns the saved entity (with its assigned id
  /// when the input was created without one).
  Future<LabelPreset> save(LabelPreset preset);
  Future<void> delete(String id);
}
