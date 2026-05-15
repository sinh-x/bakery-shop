import 'dart:typed_data';

import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _FakeProductService extends ProductService {
  _FakeProductService() : super(Dio());

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    return const <Product>[];
  }

  @override
  Future<String> uploadPhoto(int id, XFile file) async {
    return '/api/products/$id/photo';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uploadPhoto bumps product photo refresh tick', () async {
    final container = ProviderContainer(
      overrides: [
        productServiceProvider.overrideWithValue(_FakeProductService()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(productsProvider.notifier);
    await notifier.build();
    final before = container.read(productPhotoRefreshTickProvider);

    await notifier.uploadPhoto(
      99,
      XFile.fromData(Uint8List.fromList(const <int>[1, 2, 3]), name: 'photo.jpg'),
    );

    final after = container.read(productPhotoRefreshTickProvider);
    expect(after, before + 1);
  });
}
