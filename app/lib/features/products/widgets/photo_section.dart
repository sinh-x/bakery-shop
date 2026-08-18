import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:bakery_app/shared/labels/products.dart';

/// Product photo picker/preview tile shown at the top of the product
/// form. Displays the picked (not-yet-uploaded) photo if present,
/// otherwise the existing product photo from the API, and falls back
/// to a placeholder when neither is available.
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class PhotoSection extends StatelessWidget {
  const PhotoSection({
    super.key,
    required this.productId,
    required this.pickedPhoto,
    required this.baseUrl,
    required this.onPickPhoto,
    this.cacheBuster,
  });

  final int? productId;
  final XFile? pickedPhoto;
  final String baseUrl;
  final VoidCallback onPickPhoto;
  final String? cacheBuster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onPickPhoto,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    // Show picked photo (not yet uploaded)
    if (pickedPhoto != null) {
      return FutureBuilder<Uint8List>(
        future: pickedPhoto!.readAsBytes(),
        builder: (ctx, snap) {
          if (!snap.hasData) return _placeholder();
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                snap.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _placeholder(),
              ),
              _overlayButton(),
            ],
          );
        },
      );
    }

    // Show existing photo from API (always try if product exists)
    if (productId != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            '$baseUrl/api/products/$productId/photo${cacheBuster != null ? '?v=$cacheBuster' : ''}',
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => _placeholder(),
          ),
          _overlayButton(),
        ],
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
        SizedBox(height: 8),
        Text(ProductsLabels.choosePhoto, style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _overlayButton() {
    return Positioned(
      right: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.edit, color: Colors.white, size: 20),
      ),
    );
  }
}