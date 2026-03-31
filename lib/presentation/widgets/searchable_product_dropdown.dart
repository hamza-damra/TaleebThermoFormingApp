import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/responsive.dart';
import '../../domain/entities/product.dart';

class SearchableProductDropdown extends StatefulWidget {
  final List<Product> products;
  final Product? selectedProduct;
  final ValueChanged<Product?> onChanged;
  final Color borderColor;
  final String hintText;

  const SearchableProductDropdown({
    super.key,
    required this.products,
    required this.onChanged,
    this.selectedProduct,
    this.borderColor = Colors.grey,
    this.hintText = 'اختر المنتج',
  });

  @override
  State<SearchableProductDropdown> createState() => _SearchableProductDropdownState();
}

class _SearchableProductDropdownState extends State<SearchableProductDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Product> _filteredProducts = [];
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  void _showOverlay() {
    if (_isOpen) return;
    _isOpen = true;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = widget.products;
      } else {
        _filteredProducts = widget.products.where((product) {
          final nameLower = product.name.toLowerCase();
          final codeLower = product.itemCode.toLowerCase();
          final queryLower = query.toLowerCase();
          return nameLower.contains(queryLower) || codeLower.contains(queryLower);
        }).toList();
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final isMobile = ResponsiveHelper.isMobile(context);
    final maxHeight = isMobile ? 200.0 : 300.0;
    final itemCodeFontSize = isMobile ? 14.0 : 16.0;
    final nameFontSize = isMobile ? 11.0 : 12.0;
    final itemPadding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.borderColor.withValues(alpha: 0.3)),
              ),
              child: _filteredProducts.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      child: Text(
                        'لا توجد نتائج',
                        style: GoogleFonts.cairo(
                          fontSize: isMobile ? 14 : 16,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        final isSelected = widget.selectedProduct?.id == product.id;
                        return InkWell(
                          onTap: () {
                            widget.onChanged(product);
                            _searchController.text = product.itemCode;
                            _removeOverlay();
                            _focusNode.unfocus();
                          },
                          child: Container(
                            padding: itemPadding,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.borderColor.withValues(alpha: 0.1)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.itemCode,
                                  style: GoogleFonts.cairo(
                                    fontSize: itemCodeFontSize,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? widget.borderColor : Colors.black87,
                                  ),
                                ),
                                Text(
                                  product.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: nameFontSize,
                                    color: Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final fontSize = isMobile ? 14.0 : 18.0;
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 20);

    if (widget.selectedProduct != null && _searchController.text.isEmpty) {
      _searchController.text = widget.selectedProduct!.itemCode;
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
        },
        child: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          style: GoogleFonts.cairo(fontSize: fontSize, height: 1.2),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: GoogleFonts.cairo(fontSize: fontSize, height: 1.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor, width: 2),
            ),
            contentPadding: padding,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, size: isMobile ? 18 : 20),
                    onPressed: () {
                      _searchController.clear();
                      widget.onChanged(null);
                      _filterProducts('');
                    },
                  ),
                Icon(
                  Icons.arrow_drop_down,
                  color: widget.borderColor,
                  size: isMobile ? 22 : 24,
                ),
                SizedBox(width: isMobile ? 4 : 8),
              ],
            ),
          ),
          onChanged: _filterProducts,
          onTap: () {
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
            _showOverlay();
          },
        ),
      ),
    );
  }
}
