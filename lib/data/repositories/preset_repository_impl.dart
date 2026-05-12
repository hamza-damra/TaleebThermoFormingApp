import 'package:uuid/uuid.dart';

import '../../domain/entities/label_preset.dart';
import '../../domain/repositories/preset_repository.dart';
import '../datasources/printing_local_storage.dart';
import '../models/label_preset_model.dart';

class PresetRepositoryImpl implements PresetRepository {
  final _uuid = const Uuid();

  @override
  List<LabelPreset> getAll() {
    final customPresets = PrintingLocalStorage.presetsBox.values
        .map((model) => model.toEntity())
        .toList();

    return [...DefaultPresets.all, ...customPresets];
  }

  @override
  LabelPreset? getById(String id) {
    final defaultPreset = DefaultPresets.getById(id);
    if (defaultPreset != null) return defaultPreset;

    final model = PrintingLocalStorage.presetsBox.get(id);
    return model?.toEntity();
  }

  @override
  Future<LabelPreset> save(LabelPreset preset) async {
    if (preset.id.startsWith('default_')) {
      throw ArgumentError('لا يمكن تعديل الإعدادات الافتراضية');
    }

    final id = preset.id.isEmpty ? _uuid.v4() : preset.id;
    final presetWithId = preset.copyWith(id: id);
    final model = LabelPresetModel.fromEntity(presetWithId);
    await PrintingLocalStorage.presetsBox.put(id, model);
    return presetWithId;
  }

  @override
  Future<void> delete(String id) async {
    if (id.startsWith('default_')) {
      throw ArgumentError('لا يمكن حذف الإعدادات الافتراضية');
    }
    await PrintingLocalStorage.presetsBox.delete(id);
  }
}
