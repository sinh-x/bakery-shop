import 'dart:typed_data';

import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/services/image_cache_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _FakeProductService extends ProductService {
  _FakeProductService() : super(Dio());

  int? lastListActive;
  int? lastUpdatedId;
  int? lastUpdatedActive;

  final List<Product> _activeProducts = <Product>[
    const Product(id: 1, name: 'Banh mi', category: 'bread', active: 1),
  ];

  final List<Product> _inactiveProducts = <Product>[
    const Product(id: 2, name: 'Banh kem', category: 'cake', active: 0),
  ];

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    lastListActive = active;
    if (active == 0) {
      return List<Product>.from(_inactiveProducts);
    }
    return List<Product>.from(_activeProducts);
  }

  @override
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
    lastUpdatedId = id;
    lastUpdatedActive = active;

    final product = _inactiveProducts.firstWhere((item) => item.id == id);
    final reactivated = product.copyWith(active: active ?? product.active);
    _inactiveProducts.removeWhere((item) => item.id == id);
    _activeProducts.add(reactivated);

    return reactivated;
  }

  @override
  Future<String> uploadPhoto(int id, XFile file) async {
    return '/api/products/$id/photo';
  }
}

class _FakeImageCacheService implements ImageCacheService {
  int clearCount = 0;

  @override
  void clearProductPhotos() {
    clearCount++;
  }
}

void main() {
  test('inactiveProductsProvider loads products with active=0', () async {
    final fakeService = _FakeProductService();
    final container = ProviderContainer(
      overrides: [productServiceProvider.overrideWithValue(fakeService)],
    );
    addTearDown(container.dispose);

    final products = await container.read(inactiveProductsProvider.future);

    expect(fakeService.lastListActive, 0);
    expect(products, hasLength(1));
    expect(products.first.active, 0);
  });

  test(
    'reactivateProduct updates active=1 and refreshes product state',
    () async {
      final fakeService = _FakeProductService();
      final container = ProviderContainer(
        overrides: [productServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(productsProvider.notifier);
      await container.read(productsProvider.future);

      final reactivated = await notifier.reactivateProduct(2);
      final activeProducts = await container.read(productsProvider.future);

      expect(fakeService.lastUpdatedId, 2);
      expect(fakeService.lastUpdatedActive, 1);
      expect(reactivated.active, 1);
      expect(activeProducts.map((product) => product.id), contains(2));
    },
  );

  test('uploadPhoto bumps product photo refresh tick', () async {
    final fakeImageCacheService = _FakeImageCacheService();
    final container = ProviderContainer(
      overrides: [
        productServiceProvider.overrideWithValue(_FakeProductService()),
        imageCacheServiceProvider.overrideWithValue(fakeImageCacheService),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(productsProvider.notifier);
    await notifier.build();
    final before = container.read(productPhotoRefreshTickProvider);

    await notifier.uploadPhoto(
      99,
      XFile.fromData(
        Uint8List.fromList(const <int>[1, 2, 3]),
        name: 'photo.jpg',
      ),
    );

    final after = container.read(productPhotoRefreshTickProvider);
    expect(after, before + 1);
    expect(fakeImageCacheService.clearCount, 1);
  });
}
