import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../data/api/catalog_service.dart';
import '../data/models/catalog_photo.dart';

class CatalogNotifier extends AsyncNotifier<List<CatalogPhoto>> {
  final int productId;

  CatalogNotifier(this.productId);

  @override
  Future<List<CatalogPhoto>> build() async {
    final service = ref.read(catalogServiceProvider);
    return service.getCatalogPhotos(productId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final service = ref.read(catalogServiceProvider);
      return service.getCatalogPhotos(productId);
    });
  }

  Future<CatalogPhoto> addPhoto(
    XFile file, {
    String caption = '',
    String tags = '',
  }) async {
    final service = ref.read(catalogServiceProvider);
    final photo = await service.uploadCatalogPhoto(
      productId,
      file,
      caption: caption,
      tags: tags,
    );
    state.whenData((photos) {
      state = AsyncData([...photos, photo]);
    });
    return photo;
  }

  Future<CatalogPhoto> updatePhoto(
    int photoId, {
    String? caption,
    String? tags,
    int? position,
  }) async {
    final service = ref.read(catalogServiceProvider);
    final updated = await service.updateCatalogPhoto(
      productId,
      photoId,
      caption: caption,
      tags: tags,
      position: position,
    );
    state.whenData((photos) {
      state = AsyncData(
        photos.map((p) => p.id == photoId ? updated : p).toList(),
      );
    });
    return updated;
  }

  Future<void> deletePhoto(int photoId) async {
    final service = ref.read(catalogServiceProvider);
    await service.deleteCatalogPhoto(productId, photoId);
    state.whenData((photos) {
      state = AsyncData(photos.where((p) => p.id != photoId).toList());
    });
  }
}

final catalogProvider = AsyncNotifierProvider.family<CatalogNotifier,
    List<CatalogPhoto>, int>(
  (productId) => CatalogNotifier(productId),
);
