import 'package:bakery_app/data/models/cash_drawer_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashDrawerTransaction (DG-343 Phase 2)', () {
    test('fromJson parses all fields with signed amount and note', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '12',
        'type': 'cash_drawer_open',
        'amount': 1000000,
        'timestamp': '2026-08-01T08:00:00Z',
        'note': 'Mở quầy sáng',
      });

      expect(txn.id, '12');
      expect(txn.type, 'cash_drawer_open');
      expect(txn.amount, 1000000);
      expect(txn.timestamp, DateTime.parse('2026-08-01T08:00:00Z'));
      expect(txn.note, 'Mở quầy sáng');
      expect(txn.isInflow, isTrue);
      expect(txn.isOutflow, isFalse);
    });

    test('fromJson handles negative (outflow) amount and empty note', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '13',
        'type': 'cash_drawer_cash_out',
        'amount': -200000,
        'timestamp': '2026-08-01T10:00:00Z',
        'note': '',
      });

      expect(txn.amount, -200000);
      expect(txn.isInflow, isFalse);
      expect(txn.isOutflow, isTrue);
      expect(txn.note, '');
    });

    test('fromJson tolerates missing note/type/timestamp with safe defaults',
        () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '14',
        'amount': 0,
      });

      expect(txn.id, '14');
      expect(txn.type, '');
      expect(txn.amount, 0);
      expect(txn.timestamp, isNull);
      expect(txn.note, '');
      expect(txn.isInflow, isFalse);
      expect(txn.isOutflow, isFalse);
    });

    test('toJson round-trips through fromJson with stable fields', () {
      final original = CashDrawerTransaction.fromJson({
        'id': '15',
        'type': 'payment_transaction',
        'amount': 50000,
        'timestamp': '2026-08-01T09:30:00Z',
        'note': 'Bán bánh mì',
      });

      final roundTripped =
          CashDrawerTransaction.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.type, original.type);
      expect(roundTripped.amount, original.amount);
      expect(roundTripped.timestamp, original.timestamp);
      expect(roundTripped.note, original.note);
    });

    test('equality and hashCode keyed on id only', () {
      final a = CashDrawerTransaction(
        id: '20',
        type: 'cash_drawer_open',
        amount: 1000000,
        timestamp: DateTime.parse('2026-08-01T08:00:00Z'),
        note: 'a',
      );
      const b = CashDrawerTransaction(
        id: '20',
        type: 'cash_drawer_cash_out',
        amount: -500,
        note: 'b',
      );

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('CashDrawerTransaction (DG-343 Phase 4 — reference fields)', () {
    test('fromJson parses reference and referenceDetail for payment rows',
        () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '30',
        'type': 'payment_transaction',
        'amount': 150000,
        'timestamp': '2026-08-04T09:00:00Z',
        'note': 'Bán bánh kem',
        'reference': 'BKS-16-001',
        'referenceDetail': 'Khách A',
      });

      expect(txn.reference, 'BKS-16-001');
      expect(txn.referenceDetail, 'Khách A');
    });

    test('fromJson parses reference and referenceDetail for expense rows', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '31',
        'type': 'expense',
        'amount': -50000,
        'timestamp': '2026-08-04T10:00:00Z',
        'note': 'Chi phí vận chuyển',
        'reference': 'Chi phí vận chuyển',
        'referenceDetail': 'Phượng — Tiền mặt tại quầy',
      });

      expect(txn.reference, 'Chi phí vận chuyển');
      expect(txn.referenceDetail, 'Phượng — Tiền mặt tại quầy');
    });

    test('fromJson tolerates missing reference fields with empty defaults', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '32',
        'type': 'cash_drawer_open',
        'amount': 1000000,
        'timestamp': '2026-08-04T08:00:00Z',
        'note': 'Mở quầy',
      });

      expect(txn.reference, '');
      expect(txn.referenceDetail, '');
    });

    test('toJson round-trips reference and referenceDetail', () {
      final original = CashDrawerTransaction.fromJson({
        'id': '33',
        'type': 'payment_transaction',
        'amount': 50000,
        'timestamp': '2026-08-04T09:30:00Z',
        'note': 'sale',
        'reference': 'BKS-16-002',
        'referenceDetail': 'Khách B',
      });

      final roundTripped =
          CashDrawerTransaction.fromJson(original.toJson());

      expect(roundTripped.reference, original.reference);
      expect(roundTripped.referenceDetail, original.referenceDetail);
    });

    test('constructor defaults reference and referenceDetail to empty', () {
      const txn = CashDrawerTransaction(
        id: '34',
        type: 'cash_drawer_open',
        amount: 1000000,
      );

      expect(txn.reference, '');
      expect(txn.referenceDetail, '');
    });
  });

  group('CashDrawerTransaction (DG-363 Phase 3 — shippingAmount)', () {
    test('fromJson parses shippingAmount for bus payment rows', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '40',
        'type': 'payment_transaction',
        'amount': 200000,
        'timestamp': '2026-08-06T09:00:00Z',
        'note': 'Bán bánh kem giao xe khách',
        'shippingAmount': 30000,
      });

      expect(txn.shippingAmount, 30000);
    });

    test('fromJson defaults shippingAmount to 0 when absent', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '41',
        'type': 'cash_drawer_open',
        'amount': 1000000,
        'timestamp': '2026-08-06T08:00:00Z',
        'note': 'Mở quầy',
      });

      expect(txn.shippingAmount, 0);
    });

    test('fromJson defaults shippingAmount to 0 when null', () {
      final txn = CashDrawerTransaction.fromJson({
        'id': '42',
        'type': 'expense',
        'amount': -50000,
        'shippingAmount': null,
      });

      expect(txn.shippingAmount, 0);
    });

    test('toJson round-trips shippingAmount', () {
      final original = CashDrawerTransaction.fromJson({
        'id': '43',
        'type': 'payment_transaction',
        'amount': 200000,
        'shippingAmount': 30000,
      });

      final roundTripped =
          CashDrawerTransaction.fromJson(original.toJson());

      expect(roundTripped.shippingAmount, original.shippingAmount);
    });

    test('constructor defaults shippingAmount to 0', () {
      const txn = CashDrawerTransaction(
        id: '44',
        type: 'payment_transaction',
        amount: 50000,
      );

      expect(txn.shippingAmount, 0);
    });
  });

  group('CashDrawerTransactionResponse (DG-343 Phase 2)', () {
    test('fromJson parses paginated envelope with items', () {
      final resp = CashDrawerTransactionResponse.fromJson({
        'total': 2,
        'limit': 50,
        'offset': 0,
        'items': [
          {
            'id': '1',
            'type': 'cash_drawer_open',
            'amount': 1000000,
            'timestamp': '2026-08-01T08:00:00Z',
            'note': 'open',
          },
          {
            'id': '2',
            'type': 'payment_transaction',
            'amount': 50000,
            'timestamp': '2026-08-01T09:00:00Z',
            'note': 'sale',
          },
        ],
      });

      expect(resp.total, 2);
      expect(resp.limit, 50);
      expect(resp.offset, 0);
      expect(resp.items, hasLength(2));
      expect(resp.items.first.id, '1');
      expect(resp.items.first.amount, 1000000);
      expect(resp.items.last.type, 'payment_transaction');
    });

    test('fromJson returns empty items list when items missing or non-list',
        () {
      final noItems =
          CashDrawerTransactionResponse.fromJson({'total': 0});
      expect(noItems.items, isEmpty);

      final nonListItems =
          CashDrawerTransactionResponse.fromJson({'items': 'nope'});
      expect(nonListItems.items, isEmpty);
    });

    test('fromJson applies safe defaults for missing pagination fields', () {
      final resp = CashDrawerTransactionResponse.fromJson({'items': []});

      expect(resp.total, 0);
      expect(resp.limit, 50);
      expect(resp.offset, 0);
    });
  });
}