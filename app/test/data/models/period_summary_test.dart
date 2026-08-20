import 'package:bakery_app/data/models/period_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeriodSummary (DG-386 Phase 5)', () {
    test('fromJson parses a complete week payload', () {
      final json = <String, dynamic>{
        'period': 'week',
        'startDate': '2026-08-11',
        'endDate': '2026-08-17',
        'date': '2026-08-13',
        'revenue': 1200000,
        'orderCount': 18,
        'cashTotal': 700000,
        'bankTransferTotal': 500000,
        'cashInTotal': 50000,
        'cashOutTotal': 20000,
        'orders': [
          <String, dynamic>{
            'id': 'ord-1',
            'orderRef': 'ORD-1',
            'customerName': 'Sinh',
            'items': const [],
            'totalPrice': 200000,
            'createdAt': '2026-08-11T08:00:00Z',
            'updatedAt': '2026-08-11T08:00:00Z',
          },
          <String, dynamic>{
            'id': 'ord-2',
            'orderRef': 'ORD-2',
            'customerName': 'Linh',
            'items': const [],
            'totalPrice': 100000,
            'createdAt': '2026-08-12T08:00:00Z',
            'updatedAt': '2026-08-12T08:00:00Z',
          },
        ],
      };

      final summary = PeriodSummary.fromJson(json);

      expect(summary.period, 'week');
      expect(summary.startDate, '2026-08-11');
      expect(summary.endDate, '2026-08-17');
      expect(summary.date, '2026-08-13');
      expect(summary.revenue, 1200000);
      expect(summary.orderCount, 18);
      expect(summary.cashTotal, 700000);
      expect(summary.bankTransferTotal, 500000);
      expect(summary.cashInTotal, 50000);
      expect(summary.cashOutTotal, 20000);
      expect(summary.orders.length, 2);
      expect(summary.orders.first.orderRef, 'ORD-1');
      expect(summary.orders.last.customerName, 'Linh');
    });

    test('fromJson uses defaults for missing/zero fields', () {
      final summary = PeriodSummary.fromJson(const {});
      expect(summary.period, '');
      expect(summary.startDate, '');
      expect(summary.date, '');
      expect(summary.revenue, 0);
      expect(summary.orderCount, 0);
      expect(summary.cashTotal, 0);
      expect(summary.bankTransferTotal, 0);
      expect(summary.cashInTotal, 0);
      expect(summary.cashOutTotal, 0);
      expect(summary.orders, isEmpty);
    });

    test('fromJson parses month period with numeric orderCount', () {
      final json = <String, dynamic>{
        'period': 'month',
        'startDate': '2026-08-01',
        'endDate': '2026-08-31',
        'date': '2026-08-13',
        'revenue': 5000000.5,
        'orderCount': 120,
        'orders': const [],
      };
      final summary = PeriodSummary.fromJson(json);
      expect(summary.period, 'month');
      expect(summary.endDate, '2026-08-31');
      expect(summary.revenue, 5000000.5);
      expect(summary.orderCount, 120);
      expect(summary.orders, isEmpty);
    });
  });
}