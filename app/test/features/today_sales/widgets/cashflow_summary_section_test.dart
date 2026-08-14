import 'package:bakery_app/data/models/cashflow_summary.dart';
import 'package:bakery_app/features/today_sales/widgets/cashflow_summary_section.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CashflowSection _section({
  double inflow = 0,
  double outflow = 0,
  List<CashflowAccountMovement> perAccount = const [],
}) {
  return CashflowSection(
    inflow: inflow,
    outflow: outflow,
    perAccount: perAccount,
  );
}

CashflowSummary _summary({
  double operatingInflow = 0,
  double operatingOutflow = 0,
  double netOperatingCashFlow = 0,
  CashflowSection? customers,
  CashflowSection? suppliers,
  List<CashflowSupplierCategory> supplierCategories = const [],
  double uncategorizedSupplier = 0,
  Map<String, List<String>> childrenOf = const {},
}) {
  return CashflowSummary(
    period: 'week',
    startDate: '2026-08-11',
    endDate: '2026-08-17',
    date: '2026-08-13',
    operatingInflow: operatingInflow,
    operatingOutflow: operatingOutflow,
    netOperatingCashFlow: netOperatingCashFlow,
    customers: customers ?? _section(),
    suppliers: suppliers ?? _section(),
    supplierCategories: supplierCategories,
    uncategorizedSupplier: uncategorizedSupplier,
    childrenOf: childrenOf,
  );
}

CashflowSupplierCategory _cat(
  String name,
  double amount, {
  List<CashflowSubcategory> subcategories = const [],
}) {
  return CashflowSupplierCategory(
    name: name,
    amount: amount,
    subcategories: subcategories,
  );
}

CashflowSubcategory _sub(String name, double amount) =>
    CashflowSubcategory(name: name, amount: amount);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('CashflowSummarySection (DG-386 Phase 9 / FR5 / AC5)', () {
    testWidgets('renders section title', (tester) async {
      await tester.pumpWidget(_wrap(const CashflowSummarySection(
        summary: null,
      )));
      expect(find.text(SharedLabels.todaySalesCashflowSection), findsOneWidget);
    });

    testWidgets('renders empty state when summary is null', (tester) async {
      await tester.pumpWidget(_wrap(const CashflowSummarySection(
        summary: null,
      )));
      expect(find.text(SharedLabels.todaySalesCashflowEmpty), findsOneWidget);
    });

    testWidgets('renders empty state when summary has no activity',
        (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(),
      )));
      expect(find.text(SharedLabels.todaySalesCashflowEmpty), findsOneWidget);
    });

    testWidgets('renders inflow / outflow / net total lines', (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 5000000,
          operatingOutflow: 2000000,
          netOperatingCashFlow: 3000000,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesCashflowInflow), findsOneWidget);
      expect(find.text(SharedLabels.todaySalesCashflowOutflow), findsOneWidget);
      expect(find.text(SharedLabels.todaySalesCashflowNet), findsOneWidget);
      expect(find.text('5.000.000đ'), findsOneWidget);
      expect(find.text('2.000.000đ'), findsOneWidget);
      expect(find.text('3.000.000đ'), findsOneWidget);
    });

    testWidgets('renders supplier category name and inclusive amount',
        (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 800000,
          netOperatingCashFlow: 200000,
          supplierCategories: [_cat('Nguyên liệu', 800000)],
        ),
      )));
      expect(find.text('Nguyên liệu'), findsOneWidget);
      expect(find.text('800.000đ'), findsNWidgets(2)); // outflow + category
    });

    testWidgets('renders subcategory lines with amounts', (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 800000,
          netOperatingCashFlow: 200000,
          supplierCategories: [
            _cat('Nguyên liệu', 800000, subcategories: [
              _sub('Bột mì', 500000),
              _sub('Đường', 300000),
            ]),
          ],
        ),
      )));
      expect(find.text('Bột mì'), findsOneWidget);
      expect(find.text('500.000đ'), findsOneWidget);
      expect(find.text('Đường'), findsOneWidget);
      expect(find.text('300.000đ'), findsOneWidget);
    });

    testWidgets('renders uncategorized line when uncategorizedSupplier > 0',
        (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 700000,
          netOperatingCashFlow: 300000,
          supplierCategories: [_cat('Nguyên liệu', 500000)],
          uncategorizedSupplier: 200000,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesCashflowUncategorized),
          findsOneWidget);
      expect(find.text('200.000đ'), findsOneWidget);
    });

    testWidgets('omits uncategorized line when uncategorizedSupplier == 0',
        (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 500000,
          netOperatingCashFlow: 500000,
          supplierCategories: [_cat('Nguyên liệu', 500000)],
          uncategorizedSupplier: 0,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesCashflowUncategorized),
          findsNothing);
    });

    testWidgets('fills zero-amount subcategories from childrenOf mapping',
        (tester) async {
      // Backend reported only "Bột mì" with an amount, but the canonical
      // tree says "Nguyên liệu" also has "Đường" and "Men" — the widget
      // must render them with a 0 amount so the tree is always complete
      // (AC5 consistency with the expense section / AC4).
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 500000,
          netOperatingCashFlow: 500000,
          supplierCategories: [
            _cat('Nguyên liệu', 500000, subcategories: [
              _sub('Bột mì', 500000),
            ]),
          ],
          childrenOf: {
            'Nguyên liệu': ['Bột mì', 'Đường', 'Men'],
          },
        ),
      )));
      expect(find.text('Bột mì'), findsOneWidget);
      expect(find.text('Đường'), findsOneWidget);
      expect(find.text('Men'), findsOneWidget);
      // Zero-amount subcategories render as "0đ".
      expect(find.text('0đ'), findsNWidgets(2));
    });

    testWidgets('renders multiple supplier categories', (tester) async {
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1500000,
          operatingOutflow: 900000,
          netOperatingCashFlow: 600000,
          supplierCategories: [
            _cat('Nguyên liệu', 600000, subcategories: [
              _sub('Bột mì', 600000),
            ]),
            _cat('Nhân công', 300000),
          ],
        ),
      )));
      expect(find.text('Nguyên liệu'), findsOneWidget);
      expect(find.text('Nhân công'), findsOneWidget);
      expect(find.text('Bột mì'), findsOneWidget);
    });

    testWidgets('omits breakdown card when no supplier categories',
        (tester) async {
      // Inflow-only period (e.g. customer payments but no supplier payouts):
      // the total lines render but no breakdown card is shown.
      await tester.pumpWidget(_wrap(CashflowSummarySection(
        summary: _summary(
          operatingInflow: 1000000,
          operatingOutflow: 0,
          netOperatingCashFlow: 1000000,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesCashflowInflow), findsOneWidget);
      expect(find.text('1.000.000đ'), findsNWidgets(2)); // inflow + net
      expect(find.text('Nguyên liệu'), findsNothing);
    });
  });
}