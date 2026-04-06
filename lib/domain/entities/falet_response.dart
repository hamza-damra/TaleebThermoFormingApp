import 'falet_item.dart';

class FaletResponse {
  final List<FaletItem> faletItems;
  final int totalOpenFaletCount;
  final bool hasOpenFalet;

  const FaletResponse({
    required this.faletItems,
    required this.totalOpenFaletCount,
    required this.hasOpenFalet,
  });

  bool get isEmpty => faletItems.isEmpty;
}
