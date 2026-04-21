import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/catalog_browse_photo.dart';

class CatalogPhotoBrowseCard extends StatelessWidget {
  const CatalogPhotoBrowseCard({
    super.key,
    required this.photo,
    required this.baseUrl,
  });

  final CatalogBrowsePhoto photo;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final url =
        '$baseUrl/api/products/${photo.productId}/catalog/${photo.id}/photo';
    final tags = photo.tags.isNotEmpty
        ? photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty)
        : <String>[];

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
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags.take(3).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tag,
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
