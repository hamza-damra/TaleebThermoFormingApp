import 'package:uuid/uuid.dart';

import '../../domain/entities/printer_config.dart';
import '../../domain/repositories/printer_repository.dart';
import '../datasources/printing_local_storage.dart';
import '../models/printer_config_model.dart';

class PrinterRepositoryImpl implements PrinterRepository {
  final _uuid = const Uuid();

  @override
  List<PrinterConfig> getAll() {
    return PrintingLocalStorage.printersBox.values
        .map((model) => model.toEntity())
        .toList();
  }

  @override
  PrinterConfig? getById(String id) {
    final model = PrintingLocalStorage.printersBox.get(id);
    return model?.toEntity();
  }

  @override
  PrinterConfig? getDefault() {
    final printers = getAll();
    if (printers.isEmpty) return null;

    try {
      return printers.firstWhere((p) => p.isDefault);
    } catch (_) {
      return printers.first;
    }
  }

  @override
  Future<void> save(PrinterConfig printer) async {
    final id = printer.id.isEmpty ? _uuid.v4() : printer.id;
    final printerWithId = printer.copyWith(id: id);
    final model = PrinterConfigModel.fromEntity(printerWithId);
    await PrintingLocalStorage.printersBox.put(id, model);
  }

  @override
  Future<void> delete(String id) async {
    await PrintingLocalStorage.printersBox.delete(id);
  }

  @override
  Future<void> setDefault(String id) async {
    final printers = getAll();
    
    for (final printer in printers) {
      final shouldBeDefault = printer.id == id;
      if (printer.isDefault != shouldBeDefault) {
        final updated = printer.copyWith(isDefault: shouldBeDefault);
        await save(updated);
      }
    }
  }
}
