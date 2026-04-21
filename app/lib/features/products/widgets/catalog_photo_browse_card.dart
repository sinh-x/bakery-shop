import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/catalog_browse_photo.dart';
import 'catalog_tag_chips.dart';

class CatalogPhotoBrowseCard extends ConsumerWidget {
  const CatalogPhotoBrowseCard({
    super.key,
    required this.photo,
    required this.baseUrl,
  });

  final CatalogBrowsePhoto photo;
  final String baseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url =
        '$baseUrl/api/products/${photo.productId}/catalog/${photo.id}/photo';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/products/${photo.productId}/catalog',
            extra: photo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
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
}
