import '../../domain/entities/loose_balance_item.dart';
import '../../domain/entities/open_items_response.dart';
import '../../domain/entities/received_incomplete_pallet.dart';

class LooseBalanceItemModel extends LooseBalanceItem {
  const LooseBalanceItemModel({
    required super.productTypeId,
    required super.productTypeName,
    required super.loosePackageCount,
    required super.origin,
    super.sourceHandoverId,
  });

  factory LooseBalanceItemModel.fromJson(Map<String, dynamic> json) {
    return LooseBalanceItemModel(
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String,
      loosePackageCount: json['loosePackageCount'] as int,
      origin: json['origin'] as String,
      sourceHandoverId: json['sourceHandoverId'] as int?,
    );
  }
}

class ReceivedIncompletePalletModel extends ReceivedIncompletePallet {
  const ReceivedIncompletePalletModel({
    required super.id,
    required super.productTypeId,
    required super.productTypeName,
    required super.quantity,
    required super.sourceHandoverId,
    required super.status,
    required super.receivedAt,
    required super.receivedAtDisplay,
  });

  factory ReceivedIncompletePalletModel.fromJson(Map<String, dynamic> json) {
    return ReceivedIncompletePalletModel(
      id: json['id'] as int,
      productTypeId: json['productTypeId'] as int,
      productTypeName: json['productTypeName'] as String,
      quantity: json['quantity'] as int,
      sourceHandoverId: json['sourceHandoverId'] as int,
      status: json['status'] as String,
      receivedAt: DateTime.parse(json['receivedAt'] as String),
      receivedAtDisplay: json['receivedAtDisplay'] as String? ?? '',
    );
  }
}

class OpenItemsResponseModel extends OpenItemsResponse {
  const OpenItemsResponseModel({
    required super.looseBalances,
    super.receivedIncompletePallet,
  });

  factory OpenItemsResponseModel.fromJson(Map<String, dynamic> json) {
    final looseList = json['looseBalances'] as List<dynamic>? ?? [];
    final incompletePalletJson =
        json['receivedIncompletePallet'] as Map<String, dynamic>?;

    return OpenItemsResponseModel(
      looseBalances: looseList
          .map((item) =>
              LooseBalanceItemModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      receivedIncompletePallet: incompletePalletJson != null
          ? ReceivedIncompletePalletModel.fromJson(incompletePalletJson)
          : null,
    );
  }
}
