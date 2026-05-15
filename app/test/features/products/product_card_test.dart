import 'package:bakery_app/features/products/widgets/product_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds cache-busted display photo URL for product card', () {
    expect(
      productDisplayPhotoUrl('http://localhost:8000', 5, cacheBuster: '17'),
      'http://localhost:8000/api/products/5/photo?v=17',
    );
  });
}
