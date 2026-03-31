class PrintAttemptResult {
  final int id;
  final int palletId;
  final int attemptNumber;
  final String status;
  final DateTime createdAt;

  const PrintAttemptResult({
    required this.id,
    required this.palletId,
    required this.attemptNumber,
    required this.status,
    required this.createdAt,
  });
}
