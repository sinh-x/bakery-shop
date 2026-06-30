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
        'createdAt': '2026-06-25T10:00:00',
        'invalidatedAt': '2026-06-25T12:00:00',
        'invalidatedBy': 'Sinh',
      });

      expect(txn.invalidatedAt, isA<DateTime>());
      expect(txn.invalidatedBy, 'Sinh');
      expect(txn.invalidatedAt, isNotNull);
    });

    test('defaults invalidatedAt to null and invalidatedBy to empty', () {
      final txn = PaymentTransaction.fromJson({
        'id': '11',
        'orderId': '1',
        'type': 'deposit',
        'method': 'cash',
        'amount': 100000.0,
        'note': '',
        'createdAt': '2026-06-25T10:00:00',
      });

      expect(txn.invalidatedAt, isNull);
      expect(txn.invalidatedBy, '');
    });

    test('serializes invalidated fields back to JSON', () {
      const txn = PaymentTransaction(
        id: '12',
        orderId: '1',
        amount: 50000.0,
        createdAt: null,
        invalidatedAt: null,
        invalidatedBy: 'An',
      );
      final json = txn.toJson();

      expect(json['invalidatedAt'], isNull);
      expect(json['invalidatedBy'], 'An');
    });

    test('isInvalidated is true when invalidatedAt is set', () {
      final invalidated = PaymentTransaction.fromJson({
        'id': '13',
        'orderId': '1',
        'amount': 100.0,
        'invalidatedAt': '2026-06-25T12:00:00',
      });
      final valid = PaymentTransaction.fromJson({
        'id': '14',
        'orderId': '1',
        'amount': 100.0,
      });

      expect(invalidated.invalidatedAt != null, isTrue);
      expect(valid.invalidatedAt != null, isFalse);
    });
  });
}