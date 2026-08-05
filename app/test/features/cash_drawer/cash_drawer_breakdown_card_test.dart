import 'package:bakery_app/data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_breakdown_card.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CashDrawerTransaction _txn({
  required String id,
  required String type,
  required int amount,
}) =>
    CashDrawerTransaction(
      id: id,
      type: type,
      amount: amount,
      timestamp: DateTime.parse('2026-08-05T08:00:00Z'),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    )));

void main() {
  group('CashDrawerBreakdownCard (DG-359 Phase 1)', () {
    testWidgets(
        'FR1/FR2: renders all 6 categories with totals and counts, inflow '
        'green (+), outflow red (-)', (tester) async {
      await tester.pumpWidget(_wrap(const CashDrawerBreakdownCard(
        transactions: [
          CashDrawerTransaction(
              id: '1', type: 'cash_drawer_open', amount: 1000000),
          CashDrawerTransaction(
              id: '2', type: 'payment_transaction', amount: 50000),
          CashDrawerTransaction(
              id: '3', type: 'cash_drawer_cash_out', amount: -200000),
          CashDrawerTransaction(
              id: '4', type: 'expense', amount: -30000),
          CashDrawerTransaction(
              id: '5', type: 'cash_drawer_cash_in', amount: 100000),
          CashDrawerTransaction(
              id: '6', type: 'cash_drawer_close_adjust', amount: -5000),
        ],
      )));

      // All six category labels render (FR1).
      expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashIn), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeClose), findsOneWidget);

      // FR2: inflow rows render "+" in green, outflow rows render "-" in red.
      final saleAmount = tester.widget<Text>(find.descendant(
        of: find.widgetWithText(Row, VN.cashDrawerTxnTypeSale),
        matching: find.text('+50.000đ'),
      ));
      expect(saleAmount.style?.color, Colors.green.shade700);

      final expenseAmount = tester.widget<Text>(find.descendant(
        of: find.widgetWithText(Row, VN.cashDrawerTxnTypeExpense),
        matching: find.text('-30.000đ'),
      ));
      expect(expenseAmount.style?.color,
          Theme.of(tester.element(find.byType(MaterialApp))).colorScheme.error);
    });

    testWidgets(
        'FR5: empty state renders all 6 categories with 0 totals and 0 '
        'counts', (tester) async {
      await tester.pumpWidget(
          _wrap(const CashDrawerBreakdownCard(transactions: [])));

      // All six labels present (no blank table).
      expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashIn), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeClose), findsOneWidget);

      // Six count "0" entries — one per category row.
      expect(find.text('0'), findsNWidgets(6));

      // Eight "0đ" amount entries: six category rows + two footer totals.
      expect(find.text('0đ'), findsNWidgets(8));
    });

    testWidgets(
        'FR7: special types map to canonical categories '
        '(auto-transfer→Rút tiền, unidentified_sale→Bán hàng, '
        'owner_capital→Nạp tiền)', (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerBreakdownCard(
        transactions: [
          _txn(id: 'a', type: 'cash_drawer_auto_transfer', amount: -150000),
          _txn(id: 'b', type: 'unidentified_sale', amount: 75000),
          _txn(id: 'c', type: 'owner_capital', amount: 500000),
        ],
      )));

      // Rút tiền row aggregates the auto-transfer outflow.
      final cashOutRow = find.widgetWithText(Row, VN.cashDrawerTxnTypeCashOut);
      expect(find.descendant(
          of: cashOutRow, matching: find.text('-150.000đ')), findsOneWidget);

      // Bán hàng row aggregates the unidentified_sale inflow.
      final saleRow = find.widgetWithText(Row, VN.cashDrawerTxnTypeSale);
      expect(find.descendant(
          of: saleRow, matching: find.text('+75.000đ')), findsOneWidget);

      // Nạp tiền row aggregates the owner_capital inflow.
      final cashInRow = find.widgetWithText(Row, VN.cashDrawerTxnTypeCashIn);
      expect(find.descendant(
          of: cashInRow, matching: find.text('+500.000đ')), findsOneWidget);
    });

    testWidgets(
        'FR3: footer totals sum inflows and outflows across all '
        'categories', (tester) async {
      await tester.pumpWidget(_wrap(const CashDrawerBreakdownCard(
        transactions: [
          CashDrawerTransaction(
              id: '1', type: 'cash_drawer_open', amount: 1000000),
          CashDrawerTransaction(
              id: '2', type: 'payment_transaction', amount: 200000),
          CashDrawerTransaction(
              id: '3', type: 'expense', amount: -50000),
          CashDrawerTransaction(
              id: '4', type: 'cash_drawer_cash_out', amount: -100000),
        ],
      )));

      // Total inflow = 1.000.000 + 200.000 = 1.200.000.
      final totalIn = tester.widget<Text>(find.text('+1.200.000đ'));
      expect(totalIn.style?.color, Colors.green.shade700);

      // Total outflow = 50.000 + 100.000 = 150.000.
      final errorColor =
          Theme.of(tester.element(find.byType(MaterialApp))).colorScheme.error;
      final totalOut = tester.widget<Text>(find.text('-150.000đ'));
      expect(totalOut.style?.color, errorColor);
    });

    test('aggregateCashDrawerBreakdown returns 6 rows in fixed order', () {
      final rows = aggregateCashDrawerBreakdown(const []);
      expect(rows.length, 6);
      expect(rows[0].category, CashDrawerBreakdownCategory.sale);
      expect(rows[1].category, CashDrawerBreakdownCategory.expense);
      expect(rows[2].category, CashDrawerBreakdownCategory.cashIn);
      expect(rows[3].category, CashDrawerBreakdownCategory.cashOut);
      expect(rows[4].category, CashDrawerBreakdownCategory.open);
      expect(rows[5].category, CashDrawerBreakdownCategory.close);
      for (final r in rows) {
        expect(r.totalAmount, 0);
        expect(r.count, 0);
      }
    });
  });
}