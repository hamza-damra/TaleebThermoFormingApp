import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';

/// A reusable searchable picker dialog that displays items in a modal bottom sheet
/// with a search field for filtering.
///
/// Generic type [T] represents the item type (e.g., Operator, ProductType).
class SearchablePickerDialog<T> extends StatefulWidget {
  /// Title displayed at the top of the dialog
  final String title;

  /// Hint text for the search field
  final String searchHint;

  /// List of items to display
  final List<T> items;

  /// Currently selected item (optional)
  final T? selectedItem;

  /// Function to extract display text from an item
  final String Function(T item) displayTextExtractor;

  /// Function to extract subtitle text from an item (optional)
  final String Function(T item)? subtitleExtractor;

  /// Function to build a leading widget for an item (optional, e.g., thumbnail image)
  final Widget Function(T item)? leadingWidgetBuilder;

  /// Function to determine if an item matches the search query
  final bool Function(T item, String query) searchMatcher;

  /// Theme color for the dialog
  final Color themeColor;

  const SearchablePickerDialog({
    super.key,
    required this.title,
    required this.searchHint,
    required this.items,
    required this.displayTextExtractor,
    required this.searchMatcher,
    this.selectedItem,
    this.subtitleExtractor,
    this.leadingWidgetBuilder,
    this.themeColor = Colors.blue,
  });

  /// Shows the picker dialog and returns the selected item
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String searchHint,
    required List<T> items,
    required String Function(T item) displayTextExtractor,
    required bool Function(T item, String query) searchMatcher,
    T? selectedItem,
    String Function(T item)? subtitleExtractor,
    Widget Function(T item)? leadingWidgetBuilder,
    Color themeColor = Colors.blue,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SearchablePickerDialog<T>(
          title: title,
          searchHint: searchHint,
          items: items,
          selectedItem: selectedItem,
          displayTextExtractor: displayTextExtractor,
          subtitleExtractor: subtitleExtractor,
          leadingWidgetBuilder: leadingWidgetBuilder,
          searchMatcher: searchMatcher,
          themeColor: themeColor,
        ),
      ),
    );
  }

  @override
  State<SearchablePickerDialog<T>> createState() =>
      _SearchablePickerDialogState<T>();
}

class _SearchablePickerDialogState<T> extends State<SearchablePickerDialog<T>> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    // Auto-focus the search field after the dialog is displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items
            .where((item) => widget.searchMatcher(item, query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenSize = MediaQuery.of(context).size;
    final maxWidth = isMobile ? screenSize.width : 500.0;
    final maxHeight = screenSize.height * 0.85;
    final titleFontSize = isMobile ? 16.0 : 18.0;
    final itemFontSize = isMobile ? 14.0 : 16.0;
    final subtitleFontSize = isMobile ? 12.0 : 13.0;
    final padding = isMobile ? 16.0 : 20.0;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Padding(
            padding: EdgeInsets.all(padding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.cairo(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: widget.themeColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: Colors.grey,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.cairo(fontSize: itemFontSize),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: GoogleFonts.cairo(
                  fontSize: itemFontSize,
                  color: Colors.grey,
                ),
                hintTextDirection: TextDirection.rtl,
                prefixIcon: Icon(
                  Icons.search,
                  color: widget.themeColor.withValues(alpha: 0.7),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _filterItems('');
                        },
                        icon: const Icon(Icons.clear, size: 20),
                        color: Colors.grey,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.themeColor, width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16,
                  vertical: isMobile ? 12 : 14,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: _filterItems,
            ),
          ),
          SizedBox(height: padding / 2),
          // Divider
          Divider(height: 1, color: Colors.grey.shade200),
          // Items list
          Flexible(
            child: _filteredItems.isEmpty
                ? _buildEmptyState(itemFontSize)
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(vertical: padding / 2),
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = widget.selectedItem == item;
                      return _buildItemTile(
                        item,
                        isSelected,
                        itemFontSize,
                        subtitleFontSize,
                        padding,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double fontSize) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا توجد نتائج',
              style: GoogleFonts.cairo(
                fontSize: fontSize,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(
    T item,
    bool isSelected,
    double fontSize,
    double subtitleFontSize,
    double padding,
  ) {
    final displayText = widget.displayTextExtractor(item);
    final subtitle = widget.subtitleExtractor?.call(item);
    final leadingWidget = widget.leadingWidgetBuilder?.call(item);

    return InkWell(
      onTap: () {
        Navigator.of(context).pop(item);
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: padding * 0.75,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.themeColor.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            if (leadingWidget != null) ...[
              leadingWidget,
              SizedBox(width: padding * 0.75),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayText,
                    style: GoogleFonts.cairo(
                      fontSize: fontSize,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected ? widget.themeColor : Colors.black87,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        fontSize: subtitleFontSize,
                        color: Colors.grey.shade600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: widget.themeColor, size: 20),
          ],
        ),
      ),
    );
  }
}
