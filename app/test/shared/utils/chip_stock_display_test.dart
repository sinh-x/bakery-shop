import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/shared/utils/chip_stock_display.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  required int id,
  required double basePrice,
  int? stockQty,
  List<PriceChip> priceChips = const [],
}) =>
    Product(
      id: id,
      name: 'Test $id',
      basePrice: basePrice,
      stockQty: stockQty,
      priceChips: priceChips,
    );

PriceChip _chip({
  required int id,
  required double price,
  int? stockQty,
}) =>
    PriceChip(
      id: id,
      label: 'Chip $id',
      price: price,
      stockQty: stockQty,
    );

void main() {
  group('baseStockQty', () {
    test('returns remaining stock after subtracting all chip stock', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 20,
        priceChips: [
          _chip(id: 1, price: 12, stockQty: 5),
          _chip(id: 2, price: 15, stockQty: 3),
        ],
      );

      expect(baseStockQty(product), 12);
    });

    test('clamps to zero when chip stock exceeds total stock', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 4,
        priceChips: [
          _chip(id: 1, price: 12, stockQty: 5),
        ],
      );

      expect(baseStockQty(product), 0);
    });

    test('treats null stockQty as zero', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: null,
        priceChips: [
          _chip(id: 1, price: 12, stockQty: 5),
        ],
      );

      expect(baseStockQty(product), 0);
    });

    test('treats null chip stockQty as zero', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 8,
        priceChips: [
          _chip(id: 1, price: 12, stockQty: null),
        ],
      );

      expect(baseStockQty(product), 8);
    });
  });

  group('backendChipIdForSelection', () {
    test('returns null for base-price chip', () {
      final product = _product(id: 1, basePrice: 10);
      final chip = _chip(id: 3, price: 10);

      expect(backendChipIdForSelection(product, chip), isNull);
    });

    test('returns chip id for non-base-price chip', () {
      final product = _product(id: 1, basePrice: 10);
      final chip = _chip(id: 5, price: 12);

      expect(backendChipIdForSelection(product, chip), 5);
    });
  });

  group('chipDisplayStockQty', () {
    test('merges base stock for base-price chip', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 20,
        priceChips: [
          _chip(id: 1, price: 10, stockQty: 4),
          _chip(id: 2, price: 12, stockQty: 3),
        ],
      );
      final baseChip = _chip(id: 1, price: 10, stockQty: 4);

      expect(chipDisplayStockQty(product, baseChip), 17);
    });

    test('returns raw chip stock for non-base-price chip', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 20,
        priceChips: [
          _chip(id: 1, price: 10, stockQty: 4),
          _chip(id: 2, price: 12, stockQty: 3),
        ],
      );
      final otherChip = _chip(id: 2, price: 12, stockQty: 3);

      expect(chipDisplayStockQty(product, otherChip), 3);
    });

    test('handles null stockQty as zero for base-price chip', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: null,
        priceChips: const [],
      );
      final baseChip = _chip(id: 1, price: 10, stockQty: null);

      expect(chipDisplayStockQty(product, baseChip), 0);
    });

    test('handles zero base stock for base-price chip', () {
      final product = _product(
        id: 1,
        basePrice: 10,
        stockQty: 5,
        priceChips: [
          _chip(id: 1, price: 10, stockQty: 2),
          _chip(id: 2, price: 12, stockQty: 6),
        ],
      );
      final baseChip = _chip(id: 1, price: 10, stockQty: 2);

      expect(chipDisplayStockQty(product, baseChip), 2);
    });
  });
}
