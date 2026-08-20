import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/products.dart';

/// "Add catalog photo" tile rendered as the trailing item in the
/// catalog gallery grid. Shows a spinner while an upload is in
/// progress and is otherwise a tappable cell that invokes [onTap].
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class AddPhotoCard extends StatelessWidget {
  const AddPhotoCard({
    super.key,
    required this.uploading,
    required this.onTap,
  });

  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: uploading ? null : onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              uploading
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.add_photo_alternate_outlined, size: 36),
              const SizedBox(height: 8),
              Text(
                ProductsLabels.addCatalogPhoto,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}