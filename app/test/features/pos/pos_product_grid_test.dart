import 'package:bakery_app/features/pos/widgets/pos_product_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pos stock cues', () {
    test('returns in-stock label and icon for high quantity', () {
      expect(posStockStatusLabel(8), 'Còn 8');
      expect(posStockStatusIcon(8), Icons.check_circle);
    });

    test('returns low-stock label and icon for small positive quantity', () {
      expect(posStockStatusLabel(2), 'Sắp hết (2)');
      expect(posStockStatusIcon(2), Icons.warning_amber);
    });

    test('returns out-of-stock label and icon at zero', () {
      expect(posStockStatusLabel(0), 'Hết hàng');
      expect(posStockStatusIcon(0), Icons.remove_circle);
    });

    test('builds cache-busted product photo URL', () {
      expect(
        posProductPhotoUrl('http://localhost:8000', 7, cacheBuster: '3'),
        'http://localhost:8000/api/products/7/photo?v=3',
      );
    });
  });
}
