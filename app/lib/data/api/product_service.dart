import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/price_chip.dart';
import '../models/product.dart';
import 'api_client.dart';

class ProductService {
  final Dio _dio;

  ProductService(this._dio);

  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    final params = <String, dynamic>{'active': active};
    if (category != null) params['category'] = category;
    if (code != null) params['code'] = code;
    if (trungBay) params['trung_bay'] = 1;

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

  Future<Product> getProductByCode(String code) async {
    final response = await _dio.get('/api/products/code/$code');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PriceChip>> getPriceChips(int productId) async {
    final response = await _dio.get('/api/products/$productId/price-chips');
    final list = response.data as List;
    return list
        .map((json) => PriceChip.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<PriceChip> createPriceChip({
    required int productId,
    required String label,
    required double price,
    required int position,
  }) async {
    final response = await _dio.post(
      '/api/products/$productId/price-chips',
      data: {
        'label': label,
        'price': price,
        'position': position,
      },
    );
    return PriceChip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PriceChip> updatePriceChip(
    int productId,
    int chipId, {
    String? label,
    double? price,
    int? position,
  }) async {
    final data = <String, dynamic>{};
    if (label != null) data['label'] = label;
    if (price != null) data['price'] = price;
    if (position != null) data['position'] = position;

    final response = await _dio.patch(
      '/api/products/$productId/price-chips/$chipId',
      data: data,
    );
    return PriceChip.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deletePriceChip(int productId, int chipId) async {
    await _dio.delete('/api/products/$productId/price-chips/$chipId');
  }

  Future<Product> createProduct({
    required String name,
    String category = 'bread',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
    String? productCode,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'category': category,
      'base_price': basePrice,
      'cost': cost,
      'recipe_notes': recipeNotes,
    };
    if (productCode != null) data['product_code'] = productCode;
    final response = await _dio.post('/api/products', data: data);
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
    String? productCode,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (category != null) data['category'] = category;
    if (basePrice != null) data['base_price'] = basePrice;
    if (cost != null) data['cost'] = cost;
    if (recipeNotes != null) data['recipe_notes'] = recipeNotes;
    if (active != null) data['active'] = active;
    if (productCode != null) data['product_code'] = productCode;

    final response = await _dio.patch('/api/products/$id', data: data);
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('/api/products/$id');
  }

  Future<String> uploadPhoto(int id, XFile file) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
    });
    final response =
        await _dio.post('/api/products/$id/photo', data: formData);
    return response.data['url'] as String;
  }

  String getPhotoUrl(int id) {
    return '${_dio.options.baseUrl}/api/products/$id/photo';
  }

  Future<void> setProductAttribute(int productId, String attributeType, String value) async {
    await _dio.post(
      '/api/products/$productId/attributes',
      data: {'attribute_type': attributeType, 'value': value},
    );
  }

  Future<void> deleteProductAttribute(int productId, String attributeType) async {
    await _dio.delete('/api/products/$productId/attributes/$attributeType');
  }
}

final productServiceProvider = Provider<ProductService>((ref) {
  final dio = ref.watch(dioProvider);
  return ProductService(dio);
});
