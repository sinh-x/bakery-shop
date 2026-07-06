import 'package:bakery_app/features/expenses/debt_list_screen.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _debtsResponse({required List<Map<String, dynamic>> creditors}) {
  final total = creditors.fold<double>(
    0.0,
    (sum, g) => sum + (g['total_owed'] as num).toDouble(),
  );
  final count = creditors.fold<int>(0, (sum, g) => sum + (g['count'] as num).toInt());
  return {
    'creditors': creditors,
    'total_owed': total,
    'count': count,
  };
}

Map<String, dynamic> _creditorGroup({
  required String name,
  required List<Map<String, dynamic>> debts,
}) {
  final total = debts.fold<double>(
    0.0,
    (sum, d) => sum + (d['remaining'] as num).toDouble(),
  );
  return {
    'creditor': name,
    'debts': debts,
    'total_owed': total,
    'count': debts.length,
  };
}

Map<String, dynamic> _debt({
  required int eventId,
  required double amount,
  required double settled,
  required double remaining,
  required String status,
  String summary = 'Chi phí nợ',
  String? timestamp,
}) {
  return {
    'event_id': eventId,
    'summary': summary,
    'vendor': 'Nhà cung cấp A',
    'amount_vnd': amount,
    'settled_amount': settled,
    'remaining': remaining,
    'status': status,
    'timestamp': timestamp,
  };
}

void main() {
  testWidgets(
    'debt list renders empty state when creditors list is empty',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DebtListScreen(
            loadDebts: ({status}) async => _debtsResponse(creditors: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.debtListEmpty), findsOneWidget);
    },
  );

  testWidgets(
    'debt list renders grouped creditors with grand total and per-debt rows',
    (tester) async {
      final response = _debtsResponse(creditors: [
        _creditorGroup(
          name: 'Nhà cung cấp A',
          debts: [
            _debt(
              eventId: 1,
              amount: 500000,
              settled: 0,
              remaining: 500000,
              status: 'unpaid',
              timestamp: '2026-07-06T10:00:00Z',
            ),
            _debt(
              eventId: 2,
              amount: 200000,
              settled: 100000,
              remaining: 100000,
              status: 'partial',
              timestamp: '2026-07-06T11:00:00Z',
            ),
          ],
        ),
        _creditorGroup(
          name: 'Nhà cung cấp B',
          debts: [
            _debt(
              eventId: 3,
              amount: 300000,
              settled: 300000,
              remaining: 0,
              status: 'paid',
              timestamp: '2026-07-06T09:00:00Z',
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: DebtListScreen(loadDebts: ({status}) async => response),
        ),
      );
      await tester.pumpAndSettle();

      // Grand total owed = 500000 + 100000 + 0 = 600000.
      expect(find.textContaining(VN.debtListTotalOwed), findsOneWidget);
      expect(find.text('Nhà cung cấp A'), findsOneWidget);
      expect(find.text('Nhà cung cấp B'), findsOneWidget);
      // Two "Thanh toán" buttons for the two non-zero remaining debts.
      expect(find.text(VN.debtListOpenSettlement), findsNWidgets(2));
      // Status chips on the debt rows (FilterChip is the strip; Chip is the
      // row status indicator). Disambiguate from the filter strip's
      // FilterChip labels by widget type.
      expect(find.widgetWithText(Chip, VN.debtStatusUnpaid), findsOneWidget);
      expect(find.widgetWithText(Chip, VN.debtStatusPartial), findsOneWidget);
      expect(find.widgetWithText(Chip, VN.debtStatusPaid), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a debt row calls onOpenSettlement with the event id',
    (tester) async {
      int? openedId;
      final response = _debtsResponse(creditors: [
        _creditorGroup(
          name: 'Nhà cung cấp A',
          debts: [
            _debt(
              eventId: 42,
              amount: 500000,
              settled: 0,
              remaining: 500000,
              status: 'unpaid',
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: DebtListScreen(
            loadDebts: ({status}) async => response,
            onOpenSettlement: (id) => openedId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(VN.debtListOpenSettlement));
      await tester.pumpAndSettle();

      expect(openedId, 42);
    },
  );

  testWidgets(
    'selecting a status filter chip triggers reload with the new status',
    (tester) async {
      String? capturedStatus;
      final response = _debtsResponse(creditors: const []);

      await tester.pumpWidget(
        MaterialApp(
          home: DebtListScreen(
            loadDebts: ({status}) async {
              capturedStatus = status;
              return response;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial load uses no status filter.
      expect(capturedStatus, isNull);

      // Tap the "Chưa trả" filter chip.
      await tester.tap(find.text(VN.debtStatusUnpaid).last);
      await tester.pumpAndSettle();

      expect(capturedStatus, 'unpaid');
    },
  );

  testWidgets(
    'debt list shows error card when loadDebts throws',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DebtListScreen(
            loadDebts: ({status}) async => throw Exception('boom'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.debtListLoadError), findsOneWidget);
    },
  );

  test(
    'expenseDebtStatusFilterApiValue maps enum to backend values',
    () {
      expect(
        expenseDebtStatusFilterApiValue(ExpenseDebtStatusFilter.all),
        '',
      );
      expect(
        expenseDebtStatusFilterApiValue(ExpenseDebtStatusFilter.unpaid),
        'unpaid',
      );
      expect(
        expenseDebtStatusFilterApiValue(ExpenseDebtStatusFilter.partial),
        'partial',
      );
      expect(
        expenseDebtStatusFilterApiValue(ExpenseDebtStatusFilter.paid),
        'paid',
      );
    },
  );

  test(
    'expenseDebtStatusFilterLabel maps enum to VN display labels',
    () {
      expect(
        expenseDebtStatusFilterLabel(ExpenseDebtStatusFilter.all),
        VN.debtListFilterAll,
      );
      expect(
        expenseDebtStatusFilterLabel(ExpenseDebtStatusFilter.unpaid),
        VN.debtStatusUnpaid,
      );
      expect(
        expenseDebtStatusFilterLabel(ExpenseDebtStatusFilter.partial),
        VN.debtStatusPartial,
      );
      expect(
        expenseDebtStatusFilterLabel(ExpenseDebtStatusFilter.paid),
        VN.debtStatusPaid,
      );
    },
  );
}