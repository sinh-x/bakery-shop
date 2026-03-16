import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/product_service.dart';
import '../data/models/product.dart';

class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return _fetchProducts();
  }

  Future<List<Product>> _fetchProducts({String? category}) async {
    final service = ref.read(productServiceProvider);
    return service.listProducts(category: category);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchProducts());
  }

  Future<Product> createProduct({
    required String name,
    String category = 'cake',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
  }) async {
    final service = ref.read(productServiceProvider);
    final product = await service.createProduct(
      name: name,
      category: category,
      basePrice: basePrice,
      cost: cost,
      recipeNotes: recipeNotes,
    );
    await refresh();
    return product;
  }

  Future<Product> updateProduct(
    int id, {
    String? name,
    String? category,
    double? basePrice,
    double? cost,
    String? recipeNotes,
  }) async {
    final service = ref.read(productServiceProvider);
    final product = await service.updateProduct(
      id,
      name: name,
      category: category,
      basePrice: basePrice,
      cost: cost,
      recipeNotes: recipeNotes,
    );
    await refresh();
    return product;
  }

  Future<void> deleteProduct(int id) async {
    final service = ref.read(productServiceProvider);
    await service.deleteProduct(id);
    await refresh();
  }

  Future<String> uploadPhoto(int id, String filePath) async {
    final service = ref.read(productServiceProvider);
    final photoPath = await service.uploadPhoto(id, filePath);
    await refresh();
    return photoPath;
  }
}

final productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(
        ProductsNotifier.new);
