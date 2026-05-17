import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:bakery_app/shared/services/image_cache_service.dart';

import '../data/api/product_service.dart';
import '../data/models/product.dart';
import 'catalog_provider.dart';

class ProductPhotoRefreshTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final productPhotoRefreshTickProvider =
    NotifierProvider<ProductPhotoRefreshTickNotifier, int>(
      ProductPhotoRefreshTickNotifier.new,
    );

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
    state = await AsyncValue.guard(_fetchProducts);
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
    int? active,
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
      active: active,
      productCode: productCode,
    );
    await refresh();
    ref.invalidate(inactiveProductsProvider);
    if (category != null) {
      ref.invalidate(catalogBrowseProvider);
    }
    return product;
  }

  Future<void> deleteProduct(int id) async {
    final service = ref.read(productServiceProvider);
    await service.deleteProduct(id);
    await refresh();
    ref.invalidate(inactiveProductsProvider);
    ref.invalidate(catalogBrowseProvider);
  }

  Future<Product> reactivateProduct(int id) async {
    final product = await updateProduct(id, active: 1);
    ref.invalidate(inactiveProductsProvider);
    ref.invalidate(catalogBrowseProvider);
    return product;
  }

  Future<String> uploadPhoto(int id, XFile file) async {
    final service = ref.read(productServiceProvider);
    final photoPath = await service.uploadPhoto(id, file);
    ref.read(productPhotoRefreshTickProvider.notifier).bump();
    ref.read(imageCacheServiceProvider).clearProductPhotos();
    ref.invalidate(catalogProvider(id));
    ref.invalidate(catalogBrowseProvider);
    await refresh();
    return photoPath;
  }
}

final productsProvider = AsyncNotifierProvider<ProductsNotifier, List<Product>>(
  ProductsNotifier.new,
);

class InactiveProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return _fetchInactiveProducts();
  }

  Future<List<Product>> _fetchInactiveProducts({String? category}) async {
    final service = ref.read(productServiceProvider);
    return service.listProducts(category: category, active: 0);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchInactiveProducts);
  }
}

final inactiveProductsProvider =
    AsyncNotifierProvider<InactiveProductsNotifier, List<Product>>(
      InactiveProductsNotifier.new,
    );

final productByIdProvider = FutureProvider.family<Product, int>((
  ref,
  id,
) async {
  final service = ref.read(productServiceProvider);
  return service.getProduct(id);
});
