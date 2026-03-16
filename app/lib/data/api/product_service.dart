import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import 'api_client.dart';

class ProductService {
  final Dio _dio;

  ProductService(this._dio);

  Future<List<Product>> listProducts({
    String? category,
    int active = 1,
  }) async {
    final params = <String, dynamic>{'active': active};
    if (category != null) params['category'] = category;

    final response = await _dio.get('/api/products', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => Product.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Product> getProduct(int id) async {
    final response = await _dio.get('/api/products/$id');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Product> createProduct({
    required String name,
    String category = 'bread',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
  }) async {
    final response = await _dio.post('/api/products', data: {
      'name': name,
      'category': category,
      'base_price': basePrice,
      'cost': cost,
      'recipe_notes': recipeNotes,
    });
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Product> updateProduct(
    int id, {
    String? name,
    String? category,
    double? basePrice,
    double? cost,
    String? recipeNotes,
    int? active,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (category != null) data['category'] = category;
    if (basePrice != null) data['base_price'] = basePrice;
    if (cost != null) data['cost'] = cost;
    if (recipeNotes != null) data['recipe_notes'] = recipeNotes;
    if (active != null) data['active'] = active;

    final response = await _dio.patch('/api/products/$id', data: data);
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('/api/products/$id');
  }

  Future<String> uploadPhoto(int id, String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final response =
        await _dio.post('/api/products/$id/photo', data: formData);
    return response.data['photo_path'] as String;
  }

  String getPhotoUrl(int id) {
    return '${_dio.options.baseUrl}/api/products/$id/photo';
  }
}

final productServiceProvider = Provider<ProductService>((ref) {
  final dio = ref.watch(dioProvider);
  return ProductService(dio);
});
