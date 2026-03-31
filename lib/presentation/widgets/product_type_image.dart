import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../data/datasources/auth_local_storage.dart';

/// A reusable widget for displaying product type images with caching and auth headers.
///
/// Handles loading states, error states, and gracefully falls back to a placeholder
/// when no image is available or when loading fails.
class ProductTypeImage extends StatefulWidget {
  /// The relative image URL from the API (e.g., "/api/v1/product-type-images/...")
  final String? imageUrl;

  /// Size of the image container
  final double size;

  /// Border radius for the image container
  final double borderRadius;

  /// Whether to show a border around the image
  final bool showBorder;

  /// Border color (defaults to grey)
  final Color? borderColor;

  /// Background color for the placeholder
  final Color? placeholderBackgroundColor;

  /// Icon to show when no image is available
  final IconData placeholderIcon;

  /// Color for the placeholder icon
  final Color? placeholderIconColor;

  /// Box fit for the image
  final BoxFit fit;

  const ProductTypeImage({
    super.key,
    this.imageUrl,
    this.size = 48,
    this.borderRadius = 8,
    this.showBorder = true,
    this.borderColor,
    this.placeholderBackgroundColor,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.placeholderIconColor,
    this.fit = BoxFit.contain,
  });

  /// Creates a small thumbnail version (40x40)
  const ProductTypeImage.thumbnail({
    super.key,
    this.imageUrl,
    this.borderRadius = 8,
    this.showBorder = true,
    this.borderColor,
    this.placeholderBackgroundColor,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.placeholderIconColor,
    this.fit = BoxFit.contain,
  }) : size = 40;

  /// Creates a medium version for cards (80x80)
  const ProductTypeImage.medium({
    super.key,
    this.imageUrl,
    this.borderRadius = 12,
    this.showBorder = true,
    this.borderColor,
    this.placeholderBackgroundColor,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.placeholderIconColor,
    this.fit = BoxFit.contain,
  }) : size = 80;

  /// Creates a large version for detail/confirmation screens (120x120)
  const ProductTypeImage.large({
    super.key,
    this.imageUrl,
    this.borderRadius = 16,
    this.showBorder = true,
    this.borderColor,
    this.placeholderBackgroundColor,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.placeholderIconColor,
    this.fit = BoxFit.contain,
  }) : size = 120;

  @override
  State<ProductTypeImage> createState() => _ProductTypeImageState();
}

class _ProductTypeImageState extends State<ProductTypeImage> {
  final AuthLocalStorage _authStorage = AuthLocalStorage();
  String? _token;
  bool _isLoadingToken = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await _authStorage.getToken();
    if (mounted) {
      setState(() {
        _token = token;
        _isLoadingToken = false;
      });
    }
  }

  String? get _fullImageUrl {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) return null;
    // The imageUrl from API is relative, prepend the base URL
    // AppConfig.baseUrl already contains /api/v1, so we need to handle that
    final baseUrl = AppConfig.baseUrl.replaceAll('/api/v1', '');
    return '$baseUrl${widget.imageUrl}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.showBorder
            ? Border.all(
                color: widget.borderColor ?? Colors.grey.shade300,
                width: 1,
              )
            : null,
        color: widget.placeholderBackgroundColor ?? Colors.grey.shade100,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    // If no image URL, show placeholder
    if (_fullImageUrl == null) {
      return _buildPlaceholder();
    }

    // If still loading token, show loading shimmer
    if (_isLoadingToken) {
      return _buildLoadingShimmer();
    }

    // Build cached network image with auth headers
    return CachedNetworkImage(
      imageUrl: _fullImageUrl!,
      httpHeaders: _token != null
          ? {'Authorization': 'Bearer $_token'}
          : null,
      fit: widget.fit,
      placeholder: (context, url) => _buildLoadingShimmer(),
      errorWidget: (context, url, error) => _buildPlaceholder(),
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        widget.placeholderIcon,
        size: widget.size * 0.5,
        color: widget.placeholderIconColor ?? Colors.grey.shade400,
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade200,
            Colors.grey.shade100,
            Colors.grey.shade200,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: widget.size * 0.3,
          height: widget.size * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
