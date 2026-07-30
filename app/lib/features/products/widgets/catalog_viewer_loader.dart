import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/catalog_photo.dart';
import '../../../providers/catalog_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import '../widgets/catalog_photo_viewer.dart';

/// Loads a product's catalog photos and opens the viewer at the requested photo.
class CatalogViewerLoader extends ConsumerWidget {
  const CatalogViewerLoader({
    super.key,
    required this.productId,
    required this.initialPhotoId,
  });

  final int productId;
  final int? initialPhotoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider(productId));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return catalogAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, stackTrace) {
        return Scaffold(
          appBar: AppBar(title: const Text(VN.catalogTitle)),
          body: const Center(child: Text(VN.apiError)),
        );
      },
      data: (photos) {
        if (photos.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text(VN.catalogTitle)),
            body: const Center(child: Text(VN.noCatalogPhotos)),
          );
        }
        final initialIndex = initialPhotoId == null
            ? 0
            : _findIndex(photos, initialPhotoId!);
        return CatalogPhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
          productId: productId,
          baseUrl: baseUrl,
        );
      },
    );
  }

  int _findIndex(List<CatalogPhoto> photos, int photoId) {
    final idx = photos.indexWhere((p) => p.id == photoId);
    return idx < 0 ? 0 : idx;
  }
}