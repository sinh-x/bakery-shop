import 'package:bakery_app/data/models/cash_drawer.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _drawerJson({
  String status = 'open',
  String? closedAt,
  int? countedOpeningBalance,
  int? countedAmount,
  int? discrepancy,
  int? closingBalance,
  Map<String, dynamic>? journalEntry,
}) {
  final json = <String, dynamic>{
    'id': '1',
    'openedAt': '2026-08-01T00:00:00Z',
    'closedAt': closedAt,
    'status': status,
    'openingBalance': 1000000,
    'countedOpeningBalance': countedOpeningBalance,
    'countedAmount': countedAmount,
    'discrepancy': discrepancy,
    'expectedBalance': 1550000,
    'closingBalance': closingBalance,
    'journalEntry': journalEntry,
  };
  return json;
}

void main() {
  group('CashDrawer (DG-324 Phase 4 / DG-347 Phase 5)', () {
    test('fromJson parses open drawer with all balance fields', () {
      final drawer = CashDrawer.fromJson(_drawerJson());

      expect(drawer.id, '1');
      expect(drawer.status, 'open');
      expect(drawer.isOpen, isTrue);
      expect(drawer.isClosed, isFalse);
      expect(drawer.openedAt, DateTime.parse('2026-08-01T00:00:00Z'));
      expect(drawer.closedAt, isNull);
      expect(drawer.openingBalance, 1000000);
      expect(drawer.expectedBalance, 1550000);
      expect(drawer.countedAmount, isNull);
      expect(drawer.discrepancy, isNull);
      expect(drawer.closingBalance, isNull);
      expect(drawer.journalEntry, isNull);
    });

    test('fromJson parses closed drawer with counted amount + discrepancy',
        () {
      final drawer = CashDrawer.fromJson(_drawerJson(
        status: 'closed',
        closedAt: '2026-08-01T23:59:00Z',
        countedAmount: 1540000,
        discrepancy: -10000,
        closingBalance: 1540000,
      ));

      expect(drawer.isClosed, isTrue);
      expect(drawer.isOpen, isFalse);
      expect(drawer.closedAt, DateTime.parse('2026-08-01T23:59:00Z'));
      expect(drawer.countedAmount, 1540000);
      expect(drawer.discrepancy, -10000);
      expect(drawer.discrepancyValue, -10000);
      expect(drawer.closingBalance, 1540000);
    });

    test('discrepancyValue defaults to 0 when discrepancy is null', () {
      final drawer = CashDrawer.fromJson(_drawerJson());
      expect(drawer.discrepancyValue, 0);
    });

    test('fromJson parses nested journalEntry when present', () {
      final journal = {
        'id': '42',
        'description': 'Mở quầy tiền mặt: 1000000',
        'sourceType': 'cash_drawer_open',
        'lines': <Map<String, dynamic>>[],
      };
      final drawer = CashDrawer.fromJson(_drawerJson(journalEntry: journal));

      expect(drawer.journalEntry, isNotNull);
      expect(drawer.journalEntry!.id, '42');
      expect(drawer.journalEntry!.sourceType, 'cash_drawer_open');
    });

    test('toJson round-trips back to an equivalent drawer', () {
      final original = CashDrawer.fromJson(_drawerJson(
        status: 'closed',
        closedAt: '2026-08-01T23:59:00Z',
        countedAmount: 1550000,
        discrepancy: 0,
        closingBalance: 1550000,
      ));
      final roundTripped = CashDrawer.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.status, original.status);
      expect(roundTripped.openingBalance, original.openingBalance);
      expect(roundTripped.expectedBalance, original.expectedBalance);
      expect(roundTripped.countedAmount, original.countedAmount);
      expect(roundTripped.discrepancy, original.discrepancy);
      expect(roundTripped.closingBalance, original.closingBalance);
      expect(roundTripped.openedAt?.toUtc(), original.openedAt?.toUtc());
      expect(roundTripped.closedAt?.toUtc(), original.closedAt?.toUtc());
    });

    test('toJson Omits journalEntry when null and includes it when set', () {
      final without = CashDrawer.fromJson(_drawerJson()).toJson();
      expect(without.containsKey('journalEntry'), isFalse);

      final journal = {
        'id': '42',
        'sourceType': 'cash_drawer_open',
        'lines': <Map<String, dynamic>>[],
      };
      final withJournal =
          CashDrawer.fromJson(_drawerJson(journalEntry: journal)).toJson();
      expect(withJournal.containsKey('journalEntry'), isTrue);
    });

    test('equality and hashCode are id-based', () {
      final a = CashDrawer.fromJson(_drawerJson());
      final b = CashDrawer.fromJson(_drawerJson());
      final c = CashDrawer.fromJson({
        ..._drawerJson(),
        'id': '2',
      });

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('tolerates missing balance fields by defaulting to 0', () {
      final drawer = CashDrawer.fromJson({
        'id': '1',
        'status': 'open',
      });

      expect(drawer.openingBalance, 0);
      expect(drawer.expectedBalance, 0);
      expect(drawer.closingBalance, isNull);
    });

    test(
        'DG-347 Phase 5: fromJson ignores legacy accumulator fields '
        'when present in cached/older responses (NFR1)', () {
      // Older cached responses may still carry the removed fields. They
      // must be ignored without crashing and must not surface on the model.
      final drawer = CashDrawer.fromJson({
        ..._drawerJson(),
        'cashSales': 500000,
        'ownerIn': 200000,
        'ownerOut': 100000,
        'cashExpenses': 50000,
        'tienRutIn': 300000,
        'tienRutOut': 100000,
      });

      expect(drawer.openingBalance, 1000000);
      expect(drawer.expectedBalance, 1550000);
    });

    test(
        'DG-354 Phase 4 FR7: fromJson parses countedOpeningBalance when '
        'present', () {
      final drawer = CashDrawer.fromJson(_drawerJson(
        countedOpeningBalance: 950000,
      ));

      expect(drawer.countedOpeningBalance, 950000);
      // displayedOpeningBalance prefers the physical count (AC6).
      expect(drawer.displayedOpeningBalance, 950000);
      // The accounting opening balance is still available separately.
      expect(drawer.openingBalance, 1000000);
    });

    test(
        'DG-354 Phase 4 FR7: countedOpeningBalance is null and '
        'displayedOpeningBalance falls back to openingBalance for older '
        'backends', () {
      final drawer = CashDrawer.fromJson(_drawerJson());

      expect(drawer.countedOpeningBalance, isNull);
      expect(drawer.displayedOpeningBalance, drawer.openingBalance);
      expect(drawer.displayedOpeningBalance, 1000000);
    });

    test(
        'DG-354 Phase 4 FR7: toJson round-trips countedOpeningBalance', () {
      final original = CashDrawer.fromJson(_drawerJson(
        countedOpeningBalance: 950000,
      ));
      final roundTripped = CashDrawer.fromJson(original.toJson());

      expect(roundTripped.countedOpeningBalance, 950000);
      expect(roundTripped.displayedOpeningBalance, 950000);
    });

    test(
        'DG-354 Phase 4 FR7: toJson includes countedOpeningBalance (null '
        'when unset, value when set)', () {
      final without = CashDrawer.fromJson(_drawerJson()).toJson();
      expect(without.containsKey('countedOpeningBalance'), isTrue);
      expect(without['countedOpeningBalance'], isNull);

      final withCount = CashDrawer.fromJson(
        _drawerJson(countedOpeningBalance: 950000),
      ).toJson();
      expect(withCount['countedOpeningBalance'], 950000);
    });

    test(
        'DG-363 Phase 4 / FR7: fromJson parses breakdownSnapshot rows when '
        'present', () {
      final drawer = CashDrawer.fromJson({
        ..._drawerJson(),
        'breakdownSnapshot': [
          {'category': 'sale', 'totalAmount': 200000.0, 'count': 3},
          {'category': 'refund', 'totalAmount': -25000.0, 'count': 1},
          {'category': 'busShipping', 'totalAmount': 30000.0, 'count': 1},
        ],
      });

      expect(drawer.breakdownSnapshot.length, 3);
      expect(drawer.breakdownSnapshot.first.category, 'sale');
      expect(drawer.breakdownSnapshot.first.totalAmount, 200000);
      expect(drawer.breakdownSnapshot.first.count, 3);
      expect(
          drawer.breakdownSnapshot
              .firstWhere((r) => r.category == 'refund')
              .totalAmount,
          -25000);
      expect(
          drawer.breakdownSnapshot
              .firstWhere((r) => r.category == 'busShipping')
              .count,
          1);
    });

    test(
        'DG-363 Phase 4 / FR7: fromJson defaults breakdownSnapshot to empty '
        'when omitted (older responses / open drawer)', () {
      final drawer = CashDrawer.fromJson(_drawerJson());
      expect(drawer.breakdownSnapshot, isEmpty);
    });

    test(
        'DG-363 Phase 4 / FR7: fromJson tolerates a non-list '
        'breakdownSnapshot as empty', () {
      final drawer = CashDrawer.fromJson({..._drawerJson(), 'breakdownSnapshot': null});
      expect(drawer.breakdownSnapshot, isEmpty);
    });

    test(
        'DG-363 Phase 4 / FR7: toJson round-trips breakdownSnapshot', () {
      final original = CashDrawer.fromJson({
        ..._drawerJson(),
        'breakdownSnapshot': [
          {'category': 'sale', 'totalAmount': 100.0, 'count': 1},
        ],
      });
      final roundTripped = CashDrawer.fromJson(original.toJson());
      expect(roundTripped.breakdownSnapshot.length, 1);
      expect(roundTripped.breakdownSnapshot.first.category, 'sale');
      expect(roundTripped.breakdownSnapshot.first.totalAmount, 100);
      expect(roundTripped.breakdownSnapshot.first.count, 1);
    });
  });

  group('CashDrawerHistoryResponse', () {
    test('fromJson parses paginated envelope', () {
      final json = {
        'total': 2,
        'limit': 50,
        'offset': 0,
        'items': [_drawerJson(), {..._drawerJson(), 'id': '2'}],
      };
      final resp = CashDrawerHistoryResponse.fromJson(json);

      expect(resp.total, 2);
      expect(resp.limit, 50);
      expect(resp.offset, 0);
      expect(resp.items.length, 2);
      expect(resp.items.first.id, '1');
      expect(resp.items.last.id, '2');
    });

    test('fromJson handles missing items as empty list', () {
      final resp = CashDrawerHistoryResponse.fromJson({'total': 0});
      expect(resp.items, isEmpty);
      expect(resp.total, 0);
    });
  });
}