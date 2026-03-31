import 'package:equatable/equatable.dart';

import '../../core/constants/printing_constants.dart';

class PrinterConfig extends Equatable {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool isDefault;
  final int timeoutMs;

  const PrinterConfig({
    required this.id,
    required this.name,
    required this.ip,
    this.port = PrintingConstants.defaultPort,
    this.isDefault = false,
    this.timeoutMs = PrintingConstants.connectionTimeoutMs,
  });

  PrinterConfig copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    bool? isDefault,
    int? timeoutMs,
  }) {
    return PrinterConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      isDefault: isDefault ?? this.isDefault,
      timeoutMs: timeoutMs ?? this.timeoutMs,
    );
  }

  @override
  List<Object?> get props => [id, name, ip, port, isDefault, timeoutMs];
}
