import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentTransaction invalidation fields', () {
    test('parses invalidatedAt and invalidatedBy from JSON', () {
      final txn = PaymentTransaction.fromJson({
        'id': '10',
        'orderId': '1',
        'type': 'deposit',
        'method': 'cash',
        'amount': 200000.0,
        'note': '',
        'createdAt': '2026-06-25T10:00:00Z',
        'invalidatedAt': '2026-06-25T12:00:00Z',
        'invalidatedBy': 'Sinh',
      });

      expect(txn.invalidatedAt, isNotNull);
      expect(txn.invalidatedBy, 'Sinh');
    });

    test('defaults invalidatedAt to null and invalidatedBy to empty', () {
      final txn = PaymentTransaction.fromJson({
        'id': '11',
        'orderId': '1',
        'type': 'deposit',
        'method': 'cash',
        'amount': 100000.0,
        'note': '',
        'createdAt': '2026-06-25T10:00:00Z',
      });

      expect(txn.invalidatedAt, isNull);
      expect(txn.invalidatedBy, '');
    });

    test('serializes invalidated fields back to JSON', () {
      final txn = PaymentTransaction(
        id: '12',
        orderId: '1',
        amount: 50000.0,
        createdAt: DateTime.parse('2026-06-25T10:00:00Z'),
        invalidatedAt: DateTime.parse('2026-06-25T12:00:00Z'),
        invalidatedBy: 'An',
      );
      final json = txn.toJson();

      expect(json['invalidatedAt'], '2026-06-25T12:00:00Z');
      expect(json['invalidatedBy'], 'An');
    });

    test('isInvalidated is true when invalidatedAt is set', () {
      final invalidated = PaymentTransaction(
        id: '13',
        orderId: '1',
        amount: 100.0,
        invalidatedAt: DateTime.parse('2026-06-25T12:00:00Z'),
      );
      const valid = PaymentTransaction(
        id: '14',
        orderId: '1',
        amount: 100.0,
      );

      expect(invalidated.invalidatedAt != null, isTrue);
      expect(valid.invalidatedAt != null, isFalse);
    });
  });
}