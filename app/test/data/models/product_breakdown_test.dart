import 'package:bakery_app/data/models/product_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductBreakdown (DG-386 Phase 5)', () {
    test('fromJson parses top products + others', () {
      final json = <String, dynamic>{
        'period': 'week',
        'startDate': '2026-08-11',
        'endDate': '2026-08-17',
        'date': '2026-08-13',
        'totalRevenue': 1000000,
        'products': [
          <String, dynamic>{
            'name': 'Bánh kem',
            'quantity': 10,
            'revenue': 500000,
            'percentage': 50.0,
          },
          <String, dynamic>{
            'name': 'Bánh mì',
            'quantity': 20,
            'revenue': 300000,
            'percentage': 30.0,
          },
        ],
        'others': <String, dynamic>{
          'name': 'Khác',
          'quantity': 5,
          'revenue': 200000,
          'percentage': 20.0,
        },
      };

      final breakdown = ProductBreakdown.fromJson(json);

      expect(breakdown.period, 'week');
      expect(breakdown.startDate, '2026-08-11');
      expect(breakdown.endDate, '2026-08-17');
      expect(breakdown.date, '2026-08-13');
      expect(breakdown.totalRevenue, 1000000);
      expect(breakdown.products.length, 2);
      expect(breakdown.products.first.name, 'Bánh kem');
      expect(breakdown.products.first.quantity, 10);
      expect(breakdown.products.first.revenue, 500000);
      expect(breakdown.products.first.percentage, 50.0);
      expect(breakdown.others.name, 'Khác');
      expect(breakdown.others.quantity, 5);
      expect(breakdown.others.revenue, 200000);
      expect(breakdown.others.percentage, 20.0);
    });

    test('fromJson falls back to default others when missing', () {
      final json = <String, dynamic>{
        'period': 'month',
        'startDate': '2026-08-01',
        'endDate': '2026-08-31',
        'date': '2026-08-13',
        'totalRevenue': 0,
        'products': const [],
      };
      final breakdown = ProductBreakdown.fromJson(json);
      expect(breakdown.products, isEmpty);
      expect(breakdown.others.name, 'Khác');
      expect(breakdown.others.quantity, 0);
      expect(breakdown.others.revenue, 0);
      expect(breakdown.others.percentage, 0);
    });

    test('ProductBreakdownRow.fromJson handles null/missing numeric fields', () {
      final row = ProductBreakdownRow.fromJson(const {'name': 'Bánh'});
      expect(row.name, 'Bánh');
      expect(row.quantity, 0);
      expect(row.revenue, 0);
      expect(row.percentage, 0);
    });
  });
}