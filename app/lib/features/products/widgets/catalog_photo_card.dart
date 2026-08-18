import 'package:flutter/material.dart';

import '../../../data/models/catalog_photo.dart';
import 'catalog_tag_chips.dart';
import 'catalog_tag_edit_sheet.dart';
import 'package:bakery_app/shared/labels/products.dart';

/// A single catalog photo cell with image, tag chips, and edit /
/// delete / promote-to-main affordances.
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CatalogPhotoCard extends StatelessWidget {
  const CatalogPhotoCard({
    super.key,
    required this.photo,
    required this.productId,
    required this.url,
    required this.onTap,
    required this.onDelete,
    required this.onPromote,
    required this.promoting,
  });

  final CatalogPhoto photo;
  final int productId;
  final String url;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPromote;
  final bool promoting;

  void _openEditSheet(BuildContext context) {
    showEditCatalogTagsSheet(
      context: context,
      photo: photo,
      productId: productId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  // Label edit button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _openEditSheet(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.label_outline,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // Delete button
                  Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: promoting ? null : onPromote,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_outline,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                ProductsLabels.setAsProductPhoto,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tag chips row (max 3)
          if (photo.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            CatalogTagChips(tags: photo.tags, maxChips: 3),
          ],
        ],
      ),
    );
  }
}