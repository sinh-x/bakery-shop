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