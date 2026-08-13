import 'package:bakery_app/data/models/expense_summary.dart';
import 'package:bakery_app/features/today_sales/widgets/expense_summary_section.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseSummary _summary({
  double totalExpenses = 0,
  List<ExpenseCategoryBreakdown> categories = const [],
  double uncategorized = 0,
  Map<String, List<String>> childrenOf = const {},
}) {
  return ExpenseSummary(
    period: 'week',
    startDate: '2026-08-11',
    endDate: '2026-08-17',
    date: '2026-08-13',
    totalExpenses: totalExpenses,
    categories: categories,
    uncategorized: uncategorized,
    childrenOf: childrenOf,
  );
}

ExpenseCategoryBreakdown _cat(
  String name,
  double amount, {
  List<ExpenseSubcategory> subcategories = const [],
}) {
  return ExpenseCategoryBreakdown(
    name: name,
    amount: amount,
    subcategories: subcategories,
  );
}

ExpenseSubcategory _sub(String name, double amount) =>
    ExpenseSubcategory(name: name, amount: amount);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('ExpenseSummarySection (DG-386 Phase 8 / FR4 / AC4)', () {
    testWidgets('renders section title', (tester) async {
      await tester.pumpWidget(_wrap(const ExpenseSummarySection(
        summary: null,
      )));
      expect(find.text(SharedLabels.todaySalesExpenseSection), findsOneWidget);
    });

    testWidgets('renders empty state when summary is null', (tester) async {
      await tester.pumpWidget(_wrap(const ExpenseSummarySection(
        summary: null,
      )));
      expect(find.text(SharedLabels.todaySalesExpenseEmpty), findsOneWidget);
    });

    testWidgets('renders empty state when summary has no expenses',
        (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(),
      )));
      expect(find.text(SharedLabels.todaySalesExpenseEmpty), findsOneWidget);
    });

    testWidgets('renders total expenses line with formatted VND',
        (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 1200000,
          categories: [_cat('Nguyên liệu', 1200000)],
        ),
      )));
      expect(find.text(SharedLabels.todaySalesExpenseTotal), findsOneWidget);
      // Total line + the single category line both render 1.200.000đ.
      expect(find.text('1.200.000đ'), findsNWidgets(2));
    });

    testWidgets('renders parent category name and inclusive amount',
        (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 500000,
          categories: [_cat('Nguyên liệu', 500000)],
        ),
      )));
      expect(find.text('Nguyên liệu'), findsOneWidget);
      expect(find.text('500.000đ'), findsNWidgets(2)); // total + category
    });

    testWidgets('renders subcategory lines with amounts', (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 800000,
          categories: [
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

    testWidgets('fills zero-amount subcategories from childrenOf mapping',
        (tester) async {
      // Backend reported only "Bột mì" with an amount, but the canonical
      // tree says "Nguyên liệu" also has "Đường" and "Men" — the widget
      // must render them with a 0 amount so the tree is always complete.
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 500000,
          categories: [
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

    testWidgets('renders uncategorized line when uncategorized > 0',
        (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 700000,
          categories: [_cat('Nguyên liệu', 500000)],
          uncategorized: 200000,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesExpenseUncategorized),
          findsOneWidget);
      expect(find.text('200.000đ'), findsOneWidget);
    });

    testWidgets('omits uncategorized line when uncategorized == 0',
        (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 500000,
          categories: [_cat('Nguyên liệu', 500000)],
          uncategorized: 0,
        ),
      )));
      expect(find.text(SharedLabels.todaySalesExpenseUncategorized),
          findsNothing);
    });

    testWidgets('renders multiple parent categories', (tester) async {
      await tester.pumpWidget(_wrap(ExpenseSummarySection(
        summary: _summary(
          totalExpenses: 900000,
          categories: [
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
  });
}