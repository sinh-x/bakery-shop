import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import 'api_client.dart';

class CategoryService {
  final Dio _dio;

  CategoryService(this._dio);

  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    final params = <String, dynamic>{};
    if (includeInactive) params['include_inactive'] = 1;
    final response = await _dio.get('/api/categories', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory({
    required String name,
    required String slug,
    required String codePrefix,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'slug': slug,
      'code_prefix': codePrefix,
    };
    final response = await _dio.post('/api/categories', data: data);
    return Category.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Category> updateCategory(
    int id, {
    String? name,
    String? codePrefix,
    int? active,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (codePrefix != null) data['code_prefix'] = codePrefix;
    if (active != null) data['active'] = active;
    final response = await _dio.patch('/api/categories/$id', data: data);
    return Category.fromJson(response.data as Map<String, dynamic>);
  }
}

final categoryServiceProvider = Provider<CategoryService>((ref) {
  final dio = ref.watch(dioProvider);
  return CategoryService(dio);
});
