import 'package:bakery_app/features/stock/stock_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stockStatusColor', () {
    test('negative quantity returns distinct darker red shade', () {
      expect(stockStatusColor(-1), Colors.red.shade900);
      expect(stockStatusColor(-5), Colors.red.shade900);
      // Distinct from the zero (out-of-stock) red shade per FR-8.
      expect(stockStatusColor(-1), isNot(equals(stockStatusColor(0))));
    });

    test('zero returns red', () {
      expect(stockStatusColor(0), Colors.red);
    });

    test('low stock (1-3) returns orange', () {
      expect(stockStatusColor(1), Colors.orange);
      expect(stockStatusColor(3), Colors.orange);
    });

    test('healthy stock (>3) returns green', () {
      expect(stockStatusColor(4), Colors.green);
      expect(stockStatusColor(100), Colors.green);
    });
  });

  group('stockStatusLabel', () {
    test('negative quantity returns VN "Âm N" label with absolute value', () {
      expect(stockStatusLabel(-1), VN.negativeStockLabel(-1));
      expect(stockStatusLabel(-1), 'Âm 1');
      expect(stockStatusLabel(-7), 'Âm 7');
    });

    test('zero returns "Hết hàng"', () {
      expect(stockStatusLabel(0), VN.outOfStock);
      expect(stockStatusLabel(0), 'Hết hàng');
    });

    test('low stock (1-3) returns "Sắp hết"', () {
      expect(stockStatusLabel(1), 'Sắp hết');
      expect(stockStatusLabel(3), 'Sắp hết');
    });

    test('healthy stock (>3) returns "Còn hàng"', () {
      expect(stockStatusLabel(4), 'Còn hàng');
      expect(stockStatusLabel(100), 'Còn hàng');
    });
  });

  group('VN.negativeStockLabel', () {
    test('formats absolute quantity with "Âm " prefix', () {
      expect(VN.negativeStockLabel(-3), 'Âm 3');
      expect(VN.negativeStockLabel(-12), 'Âm 12');
    });
  });
}