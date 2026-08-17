import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:bakery_app/shared/services/image_cache_service.dart';
import 'package:bakery_app/shared/services/session_cache.dart';

import '../api/product_service.dart';
import '../models/product.dart';
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

  /// DG-409 Phase 5 (FR13, AC6): invalidate the session-level product cache
  /// after any product mutation so the next paginated-catalog build fetches
  /// fresh data instead of serving stale cached pages.
  void _invalidateProductSessionCache() {
    ref
        .read(sessionCacheProvider)
        .invalidateEntityType(SessionCacheEntity.products);
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
    _invalidateProductSessionCache();
    await refresh();
    ref.invalidate(phuKienProductsProvider);
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
    _invalidateProductSessionCache();
    await refresh();
    ref.invalidate(inactiveProductsProvider);
    ref.invalidate(phuKienProductsProvider);
    if (category != null) {
      ref.invalidate(catalogBrowseProvider);
    }
    return product;
  }

  Future<void> deleteProduct(int id) async {
    final service = ref.read(productServiceProvider);
    await service.deleteProduct(id);
    _invalidateProductSessionCache();
    await refresh();
    ref.invalidate(inactiveProductsProvider);
    ref.invalidate(phuKienProductsProvider);
    ref.invalidate(catalogBrowseProvider);
  }

  Future<Product> reactivateProduct(int id) async {
    // updateProduct() already invalidates the session cache (FR13).
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
    _invalidateProductSessionCache();
    await refresh();
    return photoPath;
  }
}

final productsProvider = AsyncNotifierProvider<ProductsNotifier, List<Product>>(
  ProductsNotifier.new,
);

final activeProductsByCategoryProvider =
    FutureProvider.family<List<Product>, String>((ref, category) async {
      final service = ref.read(productServiceProvider);
      return service.listProducts(category: category, active: 1);
    });

final phuKienProductsProvider = FutureProvider<List<Product>>((ref) async {
  return ref.watch(activeProductsByCategoryProvider('phu_kien').future);
});

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

// ---------------------------------------------------------------------------
// Paginated products (DG-409 Phase 4 / FR10)
// ---------------------------------------------------------------------------

/// Page size for the paginated product catalog screen.
const int productPageSize = 50;

/// Pagination-accumulation state for the product catalog (FR10, AC3).
///
/// Owns the accumulated list of loaded products, the running server-side
/// total, the current offset, and a per-list loading flag. Modeled on
/// [JournalPaginationState] so the widget's `build` method stays free of
/// side effects — re-emissions replace the page slice in state instead of
/// appending duplicates.
class ProductPaginationState {
  const ProductPaginationState({
    required this.loaded,
    required this.total,
    required this.offset,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  final List<Product> loaded;
  final int total;
  final int offset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => loaded.length < total;

  ProductPaginationState copyWith({
    List<Product>? loaded,
    int? total,
    int? offset,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ProductPaginationState(
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      offset: offset ?? this.offset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Riverpod async notifier that owns product catalog pagination accumulation
/// (FR10, AC3). The product catalog screen watches [productsPaginationProvider]
/// and calls [loadMore] when the user requests the next page.
///
/// DG-409 Phase 5 (FR13, AC5): `build()` consults the session cache first; on
/// a hit the cached [ProductPaginationState] is returned without a network
/// request. Pull-to-refresh and mutations invalidate the cache so the next
/// build re-fetches.
class ProductsPaginationNotifier extends AsyncNotifier<ProductPaginationState> {
  static const SessionCacheKey _cacheKey = SessionCacheKey(
    SessionCacheEntity.products,
  );

  @override
  Future<ProductPaginationState> build() async {
    final cache = ref.read(sessionCacheProvider);
    return cache.readOrFetch(_cacheKey, _fetchFirstPage);
  }

  Future<ProductPaginationState> _fetchFirstPage() async {
    final service = ref.read(productServiceProvider);
    final response = await service.listProductsPaginated(
      limit: productPageSize,
      offset: 0,
    );
    return ProductPaginationState(
      loaded: response.items,
      total: response.total,
      offset: response.offset,
      isLoadingMore: false,
    );
  }

  /// Fetch the next page and append it to `loaded`. No-op if already loading
  /// or no more pages remain.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final service = ref.read(productServiceProvider);
      final nextOffset = current.loaded.length;
      final response = await service.listProductsPaginated(
        limit: productPageSize,
        offset: nextOffset,
      );
      final merged = List<Product>.from(current.loaded)..addAll(response.items);
      final next = ProductPaginationState(
        loaded: merged,
        total: response.total,
        offset: nextOffset,
        isLoadingMore: false,
      );
      // Keep the cache in sync with the accumulated state so a later
      // cache hit returns the full loaded set, not just page 1 (AC5).
      ref.read(sessionCacheProvider).put(_cacheKey, next);
      state = AsyncData(next);
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  /// Re-fetch from the first page, bypassing the cache (pull-to-refresh or
  /// mutation invalidation). The cache is invalidated first so the fetch
  /// always hits the network, then re-populated with the fresh result.
  Future<void> refresh() async {
    ref
        .read(sessionCacheProvider)
        .invalidateEntityType(SessionCacheEntity.products);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      ref.invalidateSelf();
      return future;
    });
  }
}

final productsPaginationProvider =
    AsyncNotifierProvider<ProductsPaginationNotifier, ProductPaginationState>(
      ProductsPaginationNotifier.new,
    );
