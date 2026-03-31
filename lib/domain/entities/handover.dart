import 'handover_item.dart';

class Handover {
  final int id;
  final int outgoingOperatorId;
  final String outgoingOperatorName;
  final String outgoingShiftType;
  final String outgoingShiftDisplayNameAr;
  final int? incomingOperatorId;
  final String? incomingOperatorName;
  final String? incomingShiftType;
  final String? incomingShiftDisplayNameAr;
  final String status;
  final String statusDisplayNameAr;
  final List<HandoverItem> items;
  final int itemCount;
  final int totalQuantity;
  final String createdAt;
  final String createdAtDisplay;
  final String? confirmedAt;
  final String? confirmedAtDisplay;
  final String? disputedAt;
  final String? disputedAtDisplay;
  final bool blocking;
  final List<String> availableActions;
  final String? message;

  const Handover({
    required this.id,
    required this.outgoingOperatorId,
    required this.outgoingOperatorName,
    required this.outgoingShiftType,
    required this.outgoingShiftDisplayNameAr,
    this.incomingOperatorId,
    this.incomingOperatorName,
    this.incomingShiftType,
    this.incomingShiftDisplayNameAr,
    required this.status,
    required this.statusDisplayNameAr,
    required this.items,
    required this.itemCount,
    required this.totalQuantity,
    required this.createdAt,
    required this.createdAtDisplay,
    this.confirmedAt,
    this.confirmedAtDisplay,
    this.disputedAt,
    this.disputedAtDisplay,
    this.blocking = false,
    this.availableActions = const [],
    this.message,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Handover && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
