import 'package:bakery_app/data/models/cash_drawer.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_breakdown_card.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_breakdown_snapshot.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_history_list.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CashDrawer _closedDrawer({
  String id = '1',
  List<Map<String, dynamic>> snapshot = const [],
}) {
  final json = <String, dynamic>{
    'id': id,
    'openedAt': '2026-08-01T08:00:00Z',
    'closedAt': '2026-08-01T20:00:00Z',
    'status': 'closed',
    'openingBalance': 1000000,
    'expectedBalance': 1150000,
    'closingBalance': 1150000,
    'breakdownSnapshot': snapshot,
  };
  return CashDrawer.fromJson(json);
}

CashDrawer _openDrawer({String id = '2'}) {
  final json = <String, dynamic>{
    'id': id,
    'openedAt': '2026-08-02T08:00:00Z',
    'status': 'open',
    'openingBalance': 1150000,
    'expectedBalance': 1150000,
  };
  return CashDrawer.fromJson(json);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// Full 8-row snapshot (canonical categories) for a closed drawer.
const _fullSnapshot = [
  {'category': 'sale', 'totalAmount': 200000.0, 'count': 3},
  {'category': 'refund', 'totalAmount': -25000.0, 'count': 1},
  {'category': 'expense', 'totalAmount': -50000.0, 'count': 1},
  {'category': 'cashIn', 'totalAmount': 100000.0, 'count': 1},
  {'category': 'cashOut', 'totalAmount': -100000.0, 'count': 1},
  {'category': 'open', 'totalAmount': 1000000.0, 'count': 1},
  {'category': 'close', 'totalAmount': 0.0, 'count': 0},
  {'category': 'busShipping', 'totalAmount': 30000.0, 'count': 1},
];

void main() {
  group('CashDrawerHistoryList (DG-363 Phase 4 / FR7)', () {
    testWidgets(
        'AC4: closed drawer with snapshot renders CashDrawerBreakdownCard '
        'with 8 categories from the snapshot (no /transactions request)',
        (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerHistoryList(
        items: [_closedDrawer(snapshot: _fullSnapshot)],
      )));
      // Expand the closed drawer's ExpansionTile to reveal the breakdown.
      await tester.tap(find.text(formatDisplayDate(
          _closedDrawer().openedAt)));
      await tester.pumpAndSettle();

      // The breakdown card title renders (snapshot mode).
      expect(find.text(VN.cashDrawerBreakdownTitle), findsOneWidget);
      // All 8 category labels render from the snapshot.
      expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeRefund), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashIn), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeClose), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeBusShipping), findsOneWidget);
      // Both group headers render.
      expect(find.text(VN.cashDrawerBreakdownInflowGroup), findsOneWidget);
      expect(find.text(VN.cashDrawerBreakdownOutflowGroup), findsOneWidget);
    });

    testWidgets(
        'FR7/AC4: snapshot amounts render correctly (sale +200.000đ, '
        'refund -25.000đ)', (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerHistoryList(
        items: [_closedDrawer(snapshot: _fullSnapshot)],
      )));
      await tester.tap(find.text(formatDisplayDate(
          _closedDrawer().openedAt)));
      await tester.pumpAndSettle();

      final saleRow = find.widgetWithText(Row, VN.cashDrawerTxnTypeSale);
      expect(find.descendant(of: saleRow, matching: find.text('+200.000đ')),
          findsOneWidget);
      final refundRow = find.widgetWithText(Row, VN.cashDrawerTxnTypeRefund);
      expect(find.descendant(of: refundRow, matching: find.text('-25.000đ')),
          findsOneWidget);
    });

    testWidgets(
        'FR7: closed drawer with empty snapshot renders the N/A '
        'placeholder, not the breakdown card', (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerHistoryList(
        items: [_closedDrawer(snapshot: const [])],
      )));
      await tester.tap(find.text(formatDisplayDate(
          _closedDrawer().openedAt)));
      await tester.pumpAndSettle();

      // N/A label renders.
      expect(find.text(VN.cashDrawerBreakdownSnapshotNa), findsOneWidget);
      // Breakdown group headers do NOT render (no card).
      expect(find.text(VN.cashDrawerBreakdownInflowGroup), findsNothing);
      expect(find.text(VN.cashDrawerBreakdownOutflowGroup), findsNothing);
      // No per-category labels render.
      expect(find.text(VN.cashDrawerTxnTypeSale), findsNothing);
    });

    testWidgets(
        'FR7: closed drawer with missing breakdownSnapshot field (older '
        'response) also renders N/A', (tester) async {
      // Drawer built without a breakdownSnapshot key at all.
      final drawer = CashDrawer.fromJson({
        'id': '3',
        'openedAt': '2026-08-03T08:00:00Z',
        'closedAt': '2026-08-03T20:00:00Z',
        'status': 'closed',
        'openingBalance': 1000000,
        'expectedBalance': 1000000,
      });
      await tester.pumpWidget(_wrap(CashDrawerHistoryList(items: [drawer])));
      await tester.tap(find.text(formatDisplayDate(drawer.openedAt)));
      await tester.pumpAndSettle();

      expect(find.text(VN.cashDrawerBreakdownSnapshotNa), findsOneWidget);
    });

    testWidgets(
        'FR7: open drawers in history do NOT render a breakdown or N/A',
        (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerHistoryList(
        items: [_openDrawer()],
      )));
      await tester.tap(find.text(formatDisplayDate(_openDrawer().openedAt)));
      await tester.pumpAndSettle();

      // Neither the breakdown card nor the N/A placeholder render for an
      // open drawer.
      expect(find.text(VN.cashDrawerBreakdownTitle), findsNothing);
      expect(find.text(VN.cashDrawerBreakdownSnapshotNa), findsNothing);
      expect(find.text(VN.cashDrawerBreakdownInflowGroup), findsNothing);
    });
  });

  group('breakdownFromSnapshot (DG-363 Phase 4 / FR7)', () {
    test('maps all 8 canonical categories and recomputes group totals', () {
      final snapshot = _fullSnapshot.map((e) {
        final row = e as Map<String, dynamic>;
        return CashDrawerBreakdownSnapshotRow.fromJson(row);
      }).toList();
      final breakdown = breakdownFromSnapshot(snapshot);

      expect(breakdown.rows.length, 8);
      // sale row from snapshot.
      final sale = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.sale);
      expect(sale.totalAmount, 200000);
      expect(sale.count, 3);
      // refund row from snapshot.
      final refund = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.refund);
      expect(refund.totalAmount, -25000);
      expect(refund.count, 1);
      // Group totals: inflow = sale 200.000 + cashIn 100.000 + open 1.000.000
      // + busShipping 30.000 = 1.330.000.
      expect(breakdown.totalIn, 1330000);
      // outflow = |refund 25.000 + expense 50.000 + cashOut 100.000| = 175.000.
      expect(breakdown.totalOut, 175000);
      // expected = totalIn - totalOut.
      expect(breakdown.expectedBalance, 1330000 - 175000);
    });

    test('missing categories default to zero rows (always 8 rows, FR1)', () {
      // Snapshot with only 2 categories.
      final snapshot = [
        const CashDrawerBreakdownSnapshotRow(
            category: 'sale', totalAmount: 50000, count: 1),
        const CashDrawerBreakdownSnapshotRow(
            category: 'expense', totalAmount: -20000, count: 1),
      ];
      final breakdown = breakdownFromSnapshot(snapshot);

      expect(breakdown.rows.length, 8);
      // Missing categories are zero rows.
      final refund = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.refund);
      expect(refund.totalAmount, 0);
      expect(refund.count, 0);
      // Present categories keep their values.
      final sale = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.sale);
      expect(sale.totalAmount, 50000);
      expect(sale.count, 1);
    });

    test('empty snapshot yields an all-zero 8-row breakdown', () {
      final breakdown = breakdownFromSnapshot(const []);
      expect(breakdown.rows.length, 8);
      for (final r in breakdown.rows) {
        expect(r.totalAmount, 0);
        expect(r.count, 0);
      }
      expect(breakdown.totalIn, 0);
      expect(breakdown.totalOut, 0);
      expect(breakdown.expectedBalance, 0);
    });

    test('coerces float totalAmount to int for display', () {
      final snapshot = [
        const CashDrawerBreakdownSnapshotRow(
            category: 'sale', totalAmount: 99999, count: 1),
      ];
      final breakdown = breakdownFromSnapshot(snapshot);
      final sale = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.sale);
      expect(sale.totalAmount, isA<int>());
      expect(sale.totalAmount, 99999);
    });
  });
}