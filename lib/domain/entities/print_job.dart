import 'package:equatable/equatable.dart';

class PrintJob extends Equatable {
  final String value;
  final String printerId;
  final String presetId;
  final int copies;

  const PrintJob({
    required this.value,
    required this.printerId,
    required this.presetId,
    this.copies = 1,
  });

  @override
  List<Object?> get props => [value, printerId, presetId, copies];
}

enum PrintResultStatus { success, error }

class PrintResult extends Equatable {
  final PrintResultStatus status;
  final String? errorMessage;

  const PrintResult._({
    required this.status,
    this.errorMessage,
  });

  factory PrintResult.success() {
    return const PrintResult._(status: PrintResultStatus.success);
  }

  factory PrintResult.error(String message) {
    return PrintResult._(
      status: PrintResultStatus.error,
      errorMessage: message,
    );
  }

  bool get isSuccess => status == PrintResultStatus.success;
  bool get isError => status == PrintResultStatus.error;

  @override
  List<Object?> get props => [status, errorMessage];
}
