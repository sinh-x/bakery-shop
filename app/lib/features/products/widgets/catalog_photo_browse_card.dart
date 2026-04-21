import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/catalog_browse_photo.dart';
import '../../../providers/catalog_provider.dart';

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
    final tagKeys = photo.tags.isNotEmpty
        ? photo.tags
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];

    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final defs = tagDefsAsync.value;
    final labels = tagKeys.map((k) {
      if (defs == null) return k;
      for (final d in defs) {
        if (d.key == k) return d.label;
      }
      return k;
    }).toList();

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
            if (labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: labels.take(3).map((label) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }).toList(),
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
