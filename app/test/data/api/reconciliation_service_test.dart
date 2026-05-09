import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReconciliationDraftProduct.fromJson', () {
    test('merges duplicate normalized price options into one bucket', () {
      final product = ReconciliationDraftProduct.fromJson({
        'product_id': 10,
        'name': 'Banh su kem',
        'category': 'banh_ngot',
        'expected_qty': 8,
        'base_price': 130000,
        'price_chips': [
          {'id': 11, 'label': 'chip 130', 'price': 130000, 'position': 1},
          {'id': 12, 'label': 'Gia goc', 'price': 130000, 'position': 2},
        ],
        'options': [
          {
            'product_id': 10,
            'normalized_price': 130000,
            'chip_label': 'Gia goc',
            'source_chip_ids': [],
            'source_chip_labels': ['Gia goc'],
            'expected_qty': 5,
          },
          {
            'product_id': 10,
            'normalized_price': 130000,
            'chip_label': 'chip 130',
            'source_chip_ids': [11],
            'source_chip_labels': ['chip 130'],
            'expected_qty': 3,
          },
        ],
      });

      expect(product.options.length, 1);
      final option = product.options.first;
      expect(option.normalizedPrice, 130000);
      expect(option.expectedQty, 8);
      expect(option.sourceChipIds, [11]);
      expect(option.sourceChipLabels, ['Gia goc', 'chip 130']);
      expect(option.chipLabelMetadata, 'Gia goc, chip 130');
    });

    test('falls back to base price bucket when options are missing', () {
      final product = ReconciliationDraftProduct.fromJson({
        'product_id': 22,
        'name': 'Banh mi',
        'category': 'banh_ngot',
        'expected_qty': 4,
        'base_price': 120000,
        'price_chips': [],
      });

      expect(product.options.length, 1);
      final option = product.options.first;
      expect(option.normalizedPrice, 120000);
      expect(option.expectedQty, 4);
      expect(option.sourceChipIds, isEmpty);
      expect(option.sourceChipLabels, isEmpty);
      expect(option.chipLabel, 'Gia goc');
    });
  });
}
