import 'package:flutter/material.dart';

import '../../../../data/models/order_photo.dart';
import '../order_photo_section.dart';

/// Horizontal thumbnail strip for per-item photos shown inside a work item
/// card. Tapping a thumbnail opens the full-screen [OrderPhotoViewer].
class OrderWorkItemPhotoStrip extends StatelessWidget {
  const OrderWorkItemPhotoStrip({
    super.key,
    required this.photos,
    required this.baseUrl,
  });

  final List<OrderPhoto> photos;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, index) {
          final photo = photos[index];
          final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
          return GestureDetector(
            onTap: () => Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => OrderPhotoViewer(
                  photos: photos,
                  initialIndex: index,
                  baseUrl: baseUrl,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.broken_image, size: 24),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}