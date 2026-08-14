import 'package:bakery_app/data/models/product_breakdown.dart';
import 'package:bakery_app/features/today_sales/widgets/product_breakdown_section.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProductBreakdown _breakdown({
  List<ProductBreakdownRow> products = const [],
  ProductBreakdownRow? others,
  double totalRevenue = 0,
}) {
  return ProductBreakdown(
    period: 'week',
    startDate: '2026-08-11',
    endDate: '2026-08-17',
    date: '2026-08-13',
    totalRevenue: totalRevenue,
    products: products,
    others: others ??
        const ProductBreakdownRow(
            name: 'Khác', quantity: 0, revenue: 0, percentage: 0),
  );
}

ProductBreakdownRow _row(String name, int qty, double rev, double pct) =>
    ProductBreakdownRow(
        name: name, quantity: qty, revenue: rev, percentage: pct);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProductBreakdownSection (DG-386 Phase 7 / FR3 / AC3)', () {
    testWidgets('renders section title', (tester) async {
      await tester.pumpWidget(_wrap(const ProductBreakdownSection(
        breakdown: null,
      )));
      expect(find.text(SharedLabels.todaySalesProductBreakdownSection),
          findsOneWidget);
    });

    testWidgets('renders empty state when breakdown has no products',
        (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(),
      )));
      expect(find.text(SharedLabels.todaySalesProductBreakdownEmpty),
          findsOneWidget);
    });

    testWidgets('renders empty state when breakdown is null', (tester) async {
      await tester.pumpWidget(_wrap(const ProductBreakdownSection(
        breakdown: null,
      )));
      expect(find.text(SharedLabels.todaySalesProductBreakdownEmpty),
          findsOneWidget);
    });

    testWidgets('renders top products with name, qty, revenue, share',
        (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(
          totalRevenue: 1000000,
          products: [
            _row('Bánh kem', 10, 500000, 50.0),
            _row('Bánh mì', 20, 300000, 30.0),
          ],
          others: _row('Khác', 5, 200000, 20.0),
        ),
      )));
      // Column headers
      expect(find.text(SharedLabels.todaySalesProductBreakdownColumnProduct),
          findsOneWidget);
      expect(find.text(SharedLabels.todaySalesProductBreakdownColumnQuantity),
          findsOneWidget);
      expect(find.text(SharedLabels.todaySalesProductBreakdownColumnRevenue),
          findsOneWidget);
      expect(find.text(SharedLabels.todaySalesProductBreakdownColumnShare),
          findsOneWidget);
      // Product rows
      expect(find.text('Bánh kem'), findsOneWidget);
      expect(find.text('Bánh mì'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('500.000đ'), findsOneWidget);
      expect(find.text('300.000đ'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
    });

    testWidgets('renders Others row using SharedLabels label, not raw name',
        (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(
          totalRevenue: 1000000,
          products: [_row('Bánh kem', 10, 500000, 50.0)],
          others: _row('Khác', 5, 200000, 20.0),
        ),
      )));
      // The Others row must use the centralized VN label. Since the label
      // is also "Khác", we expect exactly one widget (no duplicate raw
      // string) — the product name "Khác" would otherwise collide.
      expect(find.text(SharedLabels.todaySalesProductBreakdownOthers),
          findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('200.000đ'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    });

    testWidgets('omits Others row when it has no quantity or revenue',
        (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(
          totalRevenue: 500000,
          products: [_row('Bánh kem', 10, 500000, 100.0)],
          others: const ProductBreakdownRow(
              name: 'Khác', quantity: 0, revenue: 0, percentage: 0),
        ),
      )));
      expect(find.text('Bánh kem'), findsOneWidget);
      // Others label should NOT appear when the others bucket is empty.
      expect(find.text(SharedLabels.todaySalesProductBreakdownOthers),
          findsNothing);
    });

    testWidgets('formats percentage with one decimal place', (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(
          totalRevenue: 800000,
          products: [
            _row('Bánh kem', 10, 340000, 42.5),
          ],
          others: _row('Khác', 3, 460000, 57.5),
        ),
      )));
      expect(find.text('42.5%'), findsOneWidget);
      expect(find.text('57.5%'), findsOneWidget);
    });

    testWidgets('formats whole-number percentage without decimals',
        (tester) async {
      await tester.pumpWidget(_wrap(ProductBreakdownSection(
        breakdown: _breakdown(
          totalRevenue: 1000000,
          products: [_row('Bánh kem', 10, 500000, 50.0)],
          others: _row('Khác', 5, 500000, 50.0),
        ),
      )));
      // 50.0% renders as "50%" (no trailing .0)
      expect(find.text('50%'), findsNWidgets(2));
    });
  });
}