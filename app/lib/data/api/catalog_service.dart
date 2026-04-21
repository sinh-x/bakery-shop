import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/catalog_photo.dart';
import '../models/catalog_browse_photo.dart';
import '../models/catalog_tag.dart';
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
    XFile file, {
    String caption = '',
    String tags = '',
  }) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
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

  Future<List<CatalogBrowsePhoto>> browseCatalogPhotos({
    List<String>? tags,
    int page = 1,
    int pageSize = 50,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (tags != null && tags.isNotEmpty) {
      queryParams['tags'] = tags.join(',');
    }
    final response = await _dio.get(
      '/api/catalog/photos',
      queryParameters: queryParams,
    );
    final list = response.data as List;
    return list
        .map((json) =>
            CatalogBrowsePhoto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<CatalogTagDef>> getCatalogTagDefs() async {
    final response = await _dio.get('/api/config/catalog_tag');
    final list = response.data as List;
    return list
        .where((e) => (e as Map)['active'] != false)
        .map((e) => CatalogTagDef.parse(((e as Map)['value'] as String).trim()))
        .toList();
  }
}

final catalogServiceProvider = Provider<CatalogService>((ref) {
  final dio = ref.watch(dioProvider);
  return CatalogService(dio);
});
