import '../../domain/entities/operator.dart';

class OperatorModel extends Operator {
  const OperatorModel({
    required super.id,
    required super.name,
    required super.code,
  });

  factory OperatorModel.fromJson(Map<String, dynamic> json) {
    return OperatorModel(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
    );
  }
}
