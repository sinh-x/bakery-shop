import 'package:bakery_app/shared/utils/product_photo_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('productPhotoUrl', () {
    test('builds product photo URL without cache buster', () {
      expect(
        productPhotoUrl('http://localhost:8000', 5),
        'http://localhost:8000/api/products/5/photo',
      );
    });

    test('appends cache-buster query parameter when provided', () {
      expect(
        productPhotoUrl('http://localhost:8000', 5, cacheBuster: '17'),
        'http://localhost:8000/api/products/5/photo?v=17',
      );
    });

    test('ignores empty cache buster after trimming', () {
      expect(
        productPhotoUrl('http://localhost:8000', 5, cacheBuster: '   '),
        'http://localhost:8000/api/products/5/photo',
      );
    });
  });
}
