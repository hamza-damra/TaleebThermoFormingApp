import '../../domain/entities/print_attempt_result.dart';

class PrintAttemptResultModel extends PrintAttemptResult {
  const PrintAttemptResultModel({
    required super.id,
    required super.palletId,
    required super.attemptNumber,
    required super.status,
    required super.createdAt,
  });

  factory PrintAttemptResultModel.fromJson(Map<String, dynamic> json) {
    return PrintAttemptResultModel(
      id: json['id'] as int,
      palletId: json['palleteId'] as int,
      attemptNumber: json['attemptNumber'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
