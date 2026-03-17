import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import 'api_client.dart';

class CategoryService {
  final Dio _dio;

  CategoryService(this._dio);

  Future<List<Category>> listCategories() async {
    final response = await _dio.get('/api/categories');
    final list = response.data as List;
    return list
        .map((json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final categoryServiceProvider = Provider<CategoryService>((ref) {
  final dio = ref.watch(dioProvider);
  return CategoryService(dio);
});
