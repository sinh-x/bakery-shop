import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catalog_photo.dart';
import 'api_client.dart';

class CatalogService {
  final Dio _dio;

  CatalogService(this._dio);

  Future<List<CatalogPhoto>> getCatalogPhotos(int productId) async {
    final response = await _dio.get('/api/products/$productId/catalog');
    final list = response.data as List;
    return list
        .map((json) => CatalogPhoto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CatalogPhoto> uploadCatalogPhoto(
    int productId,
    String filePath, {
    String caption = '',
    String tags = '',
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      'caption': caption,
      'tags': tags,
    });
    final response =
        await _dio.post('/api/products/$productId/catalog', data: formData);
    return CatalogPhoto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogPhoto> updateCatalogPhoto(
    int productId,
    int photoId, {
    String? caption,
    String? tags,
    int? position,
  }) async {
    final data = <String, dynamic>{};
    if (caption != null) data['caption'] = caption;
    if (tags != null) data['tags'] = tags;
    if (position != null) data['position'] = position;

    final response = await _dio.patch(
      '/api/products/$productId/catalog/$photoId',
      data: data,
    );
    return CatalogPhoto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCatalogPhoto(int productId, int photoId) async {
    await _dio.delete('/api/products/$productId/catalog/$photoId');
  }

  String getCatalogPhotoUrl(int productId, int photoId) {
    return '${_dio.options.baseUrl}/api/products/$productId/catalog/$photoId/photo';
  }
}

final catalogServiceProvider = Provider<CatalogService>((ref) {
  final dio = ref.watch(dioProvider);
  return CatalogService(dio);
});
