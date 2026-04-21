import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/catalog_photo.dart';
import '../../../data/models/catalog_browse_photo.dart';
import 'catalog_tag_chips.dart';
import 'catalog_tag_edit_sheet.dart';

class CatalogPhotoBrowseCard extends ConsumerWidget {
  const CatalogPhotoBrowseCard({
    super.key,
    required this.photo,
    required this.baseUrl,
    this.selected = false,
    this.onSelectToggle,
    this.onLongPress,
  });

  final CatalogBrowsePhoto photo;
  final String baseUrl;
  final bool selected;
  final ValueChanged<bool>? onSelectToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url =
        '$baseUrl/api/products/${photo.productId}/catalog/${photo.id}/photo';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (onSelectToggle != null) {
            onSelectToggle!(!selected);
          } else {
            context.push('/products/${photo.productId}/catalog',
                extra: photo.id);
          }
        },
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  if (onSelectToggle != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => onSelectToggle!(!selected),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? Colors.blue
                                : Colors.black.withValues(alpha: 0.5),
                          ),
                          child: selected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _openEditSheet(context),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.label_outline,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (photo.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: CatalogTagChips(
                  tags: photo.tags,
                  maxChips: 3,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: Text(
                photo.productName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    // CatalogBrowsePhoto has same id/productId/caption/tags as CatalogPhoto
    final catalogPhoto = CatalogPhoto(
      id: photo.id,
      productId: photo.productId,
      filePath: photo.filePath,
      caption: photo.caption,
      tags: photo.tags,
      position: photo.position,
      createdAt: photo.createdAt,
      photoHash: photo.photoHash,
    );
    showEditCatalogTagsSheet(
      context: context,
      photo: catalogPhoto,
      productId: photo.productId,
    );
  }
}
