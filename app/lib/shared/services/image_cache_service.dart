import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ImageCacheService {
  void clearProductPhotos();
}

class FlutterImageCacheService implements ImageCacheService {
  const FlutterImageCacheService();

  @override
  void clearProductPhotos() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

final imageCacheServiceProvider = Provider<ImageCacheService>((ref) {
  return const FlutterImageCacheService();
});
