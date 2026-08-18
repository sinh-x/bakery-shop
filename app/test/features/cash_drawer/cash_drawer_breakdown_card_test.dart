import 'package:bakery_app/data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_breakdown_card.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CashDrawerTransaction _txn({
  required String id,
  required String type,
  required int amount,
  int shippingAmount = 0,
}) =>
    CashDrawerTransaction(
      id: id,
      type: type,
      amount: amount,
      shippingAmount: shippingAmount,
      timestamp: DateTime.parse('2026-08-05T08:00:00Z'),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    )));

void main() {
  group('CashDrawerBreakdownCard (DG-359 Phase 1, DG-363 Phase 3)', () {
    testWidgets(
        'FR1/FR2: renders all 8 categories in 2 groups with totals and counts, '
        'inflow green (+), outflow red (-)', (tester) async {
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
          CashDrawerTransaction(
              id: '7', type: 'payment_transaction', amount: -25000),
          CashDrawerTransaction(
              id: '8',
              type: 'payment_transaction',
              amount: 200000,
              shippingAmount: 30000),
        ],
      )));

      // FR1: all 8 category labels render.
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeRefund), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeExpense), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeCashIn), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeCashOut), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeClose), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeBusShipping), findsOneWidget);

      // FR1: 2 group headers render.
      expect(find.text(CashDrawerLabels.cashDrawerBreakdownInflowGroup), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerBreakdownOutflowGroup), findsOneWidget);

      // FR2: inflow sale row renders "+" in green. Sale total = 50.000 +
      // 170.000 (200.000 - 30.000 shipping split) = 220.000.
      final saleAmount = tester.widget<Text>(find.descendant(
        of: find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeSale),
        matching: find.text('+220.000đ'),
      ));
      expect(saleAmount.style?.color, Colors.green.shade700);

      // FR2: outflow expense row renders "-" in red.
      final expenseAmount = tester.widget<Text>(find.descendant(
        of: find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeExpense),
        matching: find.text('-30.000đ'),
      ));
      expect(
          expenseAmount.style?.color,
          Theme.of(tester.element(find.byType(MaterialApp)))
              .colorScheme
              .error);
    });

    testWidgets(
        'FR5: empty state renders all 8 categories with 0 totals and 0 '
        'counts', (tester) async {
      await tester.pumpWidget(
          _wrap(const CashDrawerBreakdownCard(transactions: [])));

      // All 8 labels present (no blank table).
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeRefund), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeExpense), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeCashIn), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeCashOut), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeClose), findsOneWidget);
      expect(find.text(CashDrawerLabels.cashDrawerTxnTypeBusShipping), findsOneWidget);

      // 8 count "0" entries — one per category row.
      expect(find.text('0'), findsNWidgets(8));

      // Eleven "0đ" amount entries: 8 category rows + 2 group totals + 1
      // expected-balance footer row.
      expect(find.text('0đ'), findsNWidgets(11));

      // Count column header renders once per group (2 groups).
      expect(find.text(CashDrawerLabels.cashDrawerBreakdownCount), findsNWidgets(2));
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
      final cashOutRow = find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeCashOut);
      expect(find.descendant(
          of: cashOutRow, matching: find.text('-150.000đ')), findsOneWidget);

      // Bán hàng row aggregates the unidentified_sale inflow.
      final saleRow = find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeSale);
      expect(find.descendant(
          of: saleRow, matching: find.text('+75.000đ')), findsOneWidget);

      // Nạp tiền row aggregates the owner_capital inflow.
      final cashInRow = find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeCashIn);
      expect(find.descendant(
          of: cashInRow, matching: find.text('+500.000đ')), findsOneWidget);
    });

    testWidgets(
        'FR3: group totals sum inflows and outflows across all '
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

    testWidgets(
        'FR3/AC3: expected balance row = inflow - outflow', (tester) async {
      await tester.pumpWidget(_wrap(const CashDrawerBreakdownCard(
        transactions: [
          CashDrawerTransaction(
              id: '1', type: 'cash_drawer_open', amount: 1000000),
          CashDrawerTransaction(
              id: '2', type: 'payment_transaction', amount: 200000),
          CashDrawerTransaction(
              id: '3', type: 'expense', amount: -50000),
        ],
      )));

      // Expected = 1.200.000 - 50.000 = 1.150.000.
      expect(find.text('1.150.000đ'), findsOneWidget);
    });

    testWidgets(
        'FR4/AC1: payment_transaction with amount < 0 → Hoàn tiền (refund, '
        'red, negative)', (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerBreakdownCard(
        transactions: [
          _txn(id: 'r1', type: 'payment_transaction', amount: -25000),
        ],
      )));

      final refundRow =
          find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeRefund);
      expect(
          find.descendant(
              of: refundRow, matching: find.text('-25.000đ')),
          findsOneWidget);
      // Count = 1 for the refund row.
      expect(
          find.descendant(of: refundRow, matching: find.text('1')),
          findsOneWidget);
    });

    testWidgets(
        'FR5/AC2: payment_transaction with shippingAmount > 0 → Phí ship bus '
        'separated from Bán hàng', (tester) async {
      await tester.pumpWidget(_wrap(CashDrawerBreakdownCard(
        transactions: [
          _txn(
            id: 's1',
            type: 'payment_transaction',
            amount: 200000,
            shippingAmount: 30000,
          ),
        ],
      )));

      // Sale row keeps 200.000 - 30.000 = 170.000 (green inflow).
      final saleRow = find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeSale);
      expect(
          find.descendant(
              of: saleRow, matching: find.text('+170.000đ')),
          findsOneWidget);

      // busShipping row gets 30.000 (green inflow — cash the customer paid in,
      // earmarked for the bus company; displayed in the "Tiền ra" group but
      // counts toward the inflow total for reconciliation).
      final busRow =
          find.widgetWithText(Row, CashDrawerLabels.cashDrawerTxnTypeBusShipping);
      expect(
          find.descendant(
              of: busRow, matching: find.text('+30.000đ')),
          findsOneWidget);
    });

    test('aggregateCashDrawerBreakdown returns 8 rows in fixed order', () {
      final breakdown = aggregateCashDrawerBreakdown(const []);
      final rows = breakdown.rows;
      expect(rows.length, 8);
      expect(rows[0].category, CashDrawerBreakdownCategory.sale);
      expect(rows[1].category, CashDrawerBreakdownCategory.refund);
      expect(rows[2].category, CashDrawerBreakdownCategory.expense);
      expect(rows[3].category, CashDrawerBreakdownCategory.cashIn);
      expect(rows[4].category, CashDrawerBreakdownCategory.cashOut);
      expect(rows[5].category, CashDrawerBreakdownCategory.open);
      expect(rows[6].category, CashDrawerBreakdownCategory.close);
      expect(rows[7].category, CashDrawerBreakdownCategory.busShipping);
      for (final r in rows) {
        expect(r.totalAmount, 0);
        expect(r.count, 0);
      }
      expect(breakdown.totalIn, 0);
      expect(breakdown.totalOut, 0);
      expect(breakdown.expectedBalance, 0);
    });

    test('aggregateCashDrawerBreakdown splits shipping from sale (FR5)', () {
      final breakdown = aggregateCashDrawerBreakdown([
        _txn(
          id: 's1',
          type: 'payment_transaction',
          amount: 200000,
          shippingAmount: 30000,
        ),
      ]);
      final saleRow = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.sale);
      final busRow = breakdown.rows.firstWhere(
          (r) => r.category == CashDrawerBreakdownCategory.busShipping);
      expect(saleRow.totalAmount, 170000);
      expect(saleRow.count, 1);
      expect(busRow.totalAmount, 30000);
      expect(busRow.count, 1);
      // Inflow total = 170.000 + 30.000 = 200.000.
      expect(breakdown.totalIn, 200000);
      expect(breakdown.totalOut, 0);
      expect(breakdown.expectedBalance, 200000);
    });

    test('aggregateCashDrawerBreakdown classifies refund (FR4)', () {
      final breakdown = aggregateCashDrawerBreakdown([
        _txn(id: 'r1', type: 'payment_transaction', amount: -25000),
      ]);
      final refundRow = breakdown.rows
          .firstWhere((r) => r.category == CashDrawerBreakdownCategory.refund);
      expect(refundRow.totalAmount, -25000);
      expect(refundRow.count, 1);
      expect(breakdown.totalIn, 0);
      expect(breakdown.totalOut, 25000);
      expect(breakdown.expectedBalance, -25000);
    });
  });
}