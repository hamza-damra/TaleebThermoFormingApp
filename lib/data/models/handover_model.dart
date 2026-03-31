import '../../domain/entities/handover.dart';
import '../../domain/entities/handover_item.dart';
import 'handover_item_model.dart';

class HandoverModel extends Handover {
  const HandoverModel({
    required super.id,
    required super.outgoingOperatorId,
    required super.outgoingOperatorName,
    required super.outgoingShiftType,
    required super.outgoingShiftDisplayNameAr,
    super.incomingOperatorId,
    super.incomingOperatorName,
    super.incomingShiftType,
    super.incomingShiftDisplayNameAr,
    required super.status,
    required super.statusDisplayNameAr,
    required super.items,
    required super.itemCount,
    required super.totalQuantity,
    required super.createdAt,
    required super.createdAtDisplay,
    super.confirmedAt,
    super.confirmedAtDisplay,
    super.disputedAt,
    super.disputedAtDisplay,
    super.blocking,
    super.availableActions,
    super.message,
  });

  factory HandoverModel.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    final List<HandoverItem> items =
        itemsList
            ?.map(
              (item) =>
                  HandoverItemModel.fromJson(item as Map<String, dynamic>),
            )
            .toList() ??
        [];

    return HandoverModel(
      id: json['id'] as int,
      outgoingOperatorId: json['outgoingOperatorId'] as int,
      outgoingOperatorName: (json['outgoingOperatorName'] as String?) ?? '',
      outgoingShiftType: (json['outgoingShiftType'] as String?) ?? '',
      outgoingShiftDisplayNameAr:
          (json['outgoingShiftDisplayNameAr'] as String?) ?? '',
      incomingOperatorId: json['incomingOperatorId'] as int?,
      incomingOperatorName: json['incomingOperatorName'] as String?,
      incomingShiftType: json['incomingShiftType'] as String?,
      incomingShiftDisplayNameAr: json['incomingShiftDisplayNameAr'] as String?,
      status: (json['status'] as String?) ?? '',
      statusDisplayNameAr: (json['statusDisplayNameAr'] as String?) ?? '',
      items: items,
      itemCount: (json['itemCount'] as int?) ?? 0,
      totalQuantity: (json['totalQuantity'] as int?) ?? 0,
      createdAt: (json['createdAt'] as String?) ?? '',
      createdAtDisplay: (json['createdAtDisplay'] as String?) ?? '',
      confirmedAt: json['confirmedAt'] as String?,
      confirmedAtDisplay: json['confirmedAtDisplay'] as String?,
      disputedAt: json['disputedAt'] as String?,
      disputedAtDisplay: json['disputedAtDisplay'] as String?,
      blocking: json['blocking'] as bool? ?? false,
      availableActions:
          (json['availableActions'] as List<dynamic>?)?.cast<String>() ??
          const [],
      message: json['message'] as String?,
    );
  }
}
