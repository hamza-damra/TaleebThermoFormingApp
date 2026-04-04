import 'loose_balance_item.dart';
import 'received_incomplete_pallet.dart';

class OpenItemsResponse {
  final List<LooseBalanceItem> looseBalances;
  final ReceivedIncompletePallet? receivedIncompletePallet;

  const OpenItemsResponse({
    required this.looseBalances,
    this.receivedIncompletePallet,
  });

  bool get isEmpty =>
      looseBalances.isEmpty && receivedIncompletePallet == null;
}
