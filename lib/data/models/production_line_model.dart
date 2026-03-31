import '../../domain/entities/production_line.dart';

class ProductionLineModel extends ProductionLine {
  const ProductionLineModel({
    required super.id,
    required super.name,
    required super.code,
    required super.lineNumber,
  });

  factory ProductionLineModel.fromJson(Map<String, dynamic> json) {
    return ProductionLineModel(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
      lineNumber: json['lineNumber'] as int,
    );
  }
}
