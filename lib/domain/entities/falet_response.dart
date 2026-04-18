import 'falet_item.dart';

class FaletResponse {
  final List<FaletItem> faletItems;
  final int totalOpenFaletCount;
  final bool hasOpenFalet;
  final int managerResolvedFaletCount;

  const FaletResponse({
    required this.faletItems,
    required this.totalOpenFaletCount,
    required this.hasOpenFalet,
    this.managerResolvedFaletCount = 0,
  });

  bool get isEmpty => faletItems.isEmpty;
}
