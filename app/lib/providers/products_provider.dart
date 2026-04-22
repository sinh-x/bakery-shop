import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../data/api/product_service.dart';
import '../data/models/product.dart';
import 'catalog_provider.dart';

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
    String category = 'banh_kem',
    double basePrice = 0,
    double cost = 0,
    String recipeNotes = '',
    String? productCode,
  }) async {
    final service = ref.read(productServiceProvider);
    final product = await service.createProduct(
      name: name,
      category: category,
      basePrice: basePrice,
      cost: cost,
      recipeNotes: recipeNotes,
      productCode: productCode,
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
    String? productCode,
  }) async {
    final service = ref.read(productServiceProvider);
    final product = await service.updateProduct(
      id,
      name: name,
      category: category,
      basePrice: basePrice,
      cost: cost,
      recipeNotes: recipeNotes,
      productCode: productCode,
    );
    await refresh();
    if (category != null) {
      ref.invalidate(catalogBrowseProvider);
    }
    return product;
  }

  Future<void> deleteProduct(int id) async {
    final service = ref.read(productServiceProvider);
    await service.deleteProduct(id);
    await refresh();
    ref.invalidate(catalogBrowseProvider);
  }

  Future<String> uploadPhoto(int id, XFile file) async {
    final service = ref.read(productServiceProvider);
    final photoPath = await service.uploadPhoto(id, file);
    await refresh();
    return photoPath;
  }
}

final productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(
        ProductsNotifier.new);
