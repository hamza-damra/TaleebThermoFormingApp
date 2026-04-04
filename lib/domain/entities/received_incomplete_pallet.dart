class ReceivedIncompletePallet {
  final int id;
  final int productTypeId;
  final String productTypeName;
  final int quantity;
  final int sourceHandoverId;
  final String status;
  final DateTime receivedAt;
  final String receivedAtDisplay;

  const ReceivedIncompletePallet({
    required this.id,
    required this.productTypeId,
    required this.productTypeName,
    required this.quantity,
    required this.sourceHandoverId,
    required this.status,
    required this.receivedAt,
    required this.receivedAtDisplay,
  });
}
