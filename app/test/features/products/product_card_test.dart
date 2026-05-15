import 'package:bakery_app/shared/utils/product_photo_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds cache-busted display photo URL for product card', () {
    expect(
      productPhotoUrl('http://localhost:8000', 5, cacheBuster: '17'),
      'http://localhost:8000/api/products/5/photo?v=17',
    );
  });
}
