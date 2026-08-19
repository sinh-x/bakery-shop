import 'package:bakery_app/data/models/order_breakdown.dart';
import 'package:bakery_app/features/today_sales/widgets/order_breakdown_section.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Finder for the mode DropdownButton regardless of its private generic type.
final _dropdownFinder = find.byWidgetPredicate(
  (w) => w is DropdownButton,
  description: 'DropdownButton (any generic)',
);

OrderBreakdownCell _cell(
  String source,
  String deliveryType,
  int orderCount,
  double revenue,
) =>
    OrderBreakdownCell(
      source: source,
      deliveryType: deliveryType,
      orderCount: orderCount,
      revenue: revenue,
    );

OrderBreakdown _breakdown(List<OrderBreakdownCell> cells) =>
    OrderBreakdown(cells: cells);

// Wrap in a scrollable + oversized viewport so the matrix Card never overflows
// the test surface (mirrors the cashflow-summary test harness).
Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 1200,
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  group('OrderBreakdownSection (DG-391 Phase 4 / FR2 / AC1 / AC2)', () {
    testWidgets('renders section title', (tester) async {
      await tester.pumpWidget(_wrap(const OrderBreakdownSection(
        breakdown: null,
      )));
      expect(find.text(SharedLabels.todaySalesOrderBreakdownSection),
          findsOneWidget);
    });

    testWidgets('renders empty state when breakdown is null', (tester) async {
      await tester.pumpWidget(_wrap(const OrderBreakdownSection(
        breakdown: null,
      )));
      expect(find.text(SharedLabels.todaySalesOrderBreakdownEmpty),
          findsOneWidget);
    });

    testWidgets('renders empty state when breakdown has no cells',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown(const []),
      )));
      expect(find.text(SharedLabels.todaySalesOrderBreakdownEmpty),
          findsOneWidget);
    });

    testWidgets('renders source rows x delivery_type columns with order '
        'counts and revenue in default mode (FR1 / FR7 / AC1)', (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 3, 900000),
          _cell('Tại tiệm - POS', 'delivery', 1, 300000),
          _cell('Facebook-DoanGia', 'delivery', 2, 500000),
          _cell('Zalo', 'pickup', 1, 150000),
        ]),
      )));
      // Section title + source header.
      expect(find.text(SharedLabels.todaySalesOrderBreakdownSection),
          findsOneWidget);
      expect(find.text(SharedLabels.todaySalesOrderBreakdownSourceHeader),
          findsOneWidget);
      // Delivery-type column headers (alphabetically sorted: delivery, pickup).
      expect(find.text('delivery'), findsOneWidget);
      expect(find.text('pickup'), findsOneWidget);
      // FR7 fixed source order: Tại tiệm - POS, Facebook-DoanGia, Zalo.
      expect(find.text('Tại tiệm - POS'), findsOneWidget);
      expect(find.text('Facebook-DoanGia'), findsOneWidget);
      expect(find.text('Zalo'), findsOneWidget);
      // Default mode is "Số đơn + Doanh thu".
      expect(find.text(SharedLabels.todaySalesOrderBreakdownModeCountRevenue),
          findsOneWidget);
      // Order counts: "3" appears in POS-pickup cell + delivery-column total
      // (1+2=3) => 2. "2" appears only in FB-delivery cell => 1. "1" appears
      // in POS-delivery cell + Zalo-pickup cell => 2. "4" appears in the
      // pickup-column total (3+1=4) => 1.
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('4'), findsOneWidget);
      // Revenue per cell (formatVND).
      expect(find.text('900.000đ'), findsOneWidget);
      expect(find.text('300.000đ'), findsOneWidget);
      expect(find.text('500.000đ'), findsOneWidget);
      expect(find.text('150.000đ'), findsOneWidget);
      // Totals row label.
      expect(find.text(SharedLabels.todaySalesOrderBreakdownTotal),
          findsOneWidget);
    });

    testWidgets('renders missing cell as a dash placeholder', (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 2, 400000),
          _cell('Zalo', 'delivery', 1, 100000),
        ]),
      )));
      // delivery + pickup columns both present; POS has no delivery cell and
      // Zalo has no pickup cell -> two "—" placeholders in the source rows.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('default dropdown mode is "Số đơn + Doanh thu" (FR2 / AC2)',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([_cell('Zalo', 'pickup', 1, 100000)]),
      )));
      expect(find.text(SharedLabels.todaySalesOrderBreakdownModeCountRevenue),
          findsOneWidget);
      // Revenue renders in default mode — appears in the source cell and the
      // totals-row cell (single delivery type => column total == cell value).
      expect(find.text('100.000đ'), findsNWidgets(2));
    });

    testWidgets('switching dropdown to "Số đơn" shows count only (FR2 / AC2)',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 3, 900000),
          _cell('Zalo', 'delivery', 2, 500000),
        ]),
      )));
      // Initially (default mode) revenue is shown (2x: cell + column total).
      expect(find.text('900.000đ'), findsNWidgets(2));
      // Open the dropdown and select "Số đơn".
      await tester.tap(_dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text(SharedLabels.todaySalesOrderBreakdownModeCount)
          .last);
      await tester.pumpAndSettle();
      // Selected mode label is "Số đơn".
      expect(find.text(SharedLabels.todaySalesOrderBreakdownModeCount),
          findsOneWidget);
      // Revenue must be gone — only counts remain.
      expect(find.text('900.000đ'), findsNothing);
      expect(find.text('500.000đ'), findsNothing);
      // Counts still present (each appears twice: cell + column total).
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('2'), findsNWidgets(2));
    });

    testWidgets('switching dropdown to "Số đơn + Doanh thu + Tỷ trọng" shows '
        'share-of-total percentages (FR2 / AC2)', (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 3, 750000),
          _cell('Zalo', 'pickup', 1, 250000),
        ]),
      )));
      // Total revenue = 1.000.000 -> POS share 75%, Zalo share 25%, pickup
      // column total share 100%.
      await tester.tap(_dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find
          .text(SharedLabels.todaySalesOrderBreakdownModeCountRevenueShare)
          .last);
      await tester.pumpAndSettle();
      expect(
          find.text(SharedLabels.todaySalesOrderBreakdownModeCountRevenueShare),
          findsOneWidget);
      // Source-row shares.
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      // Totals-row column share.
      expect(find.text('100%'), findsOneWidget);
      // Revenue is still rendered in this mode (cell + column total).
      expect(find.text('750.000đ'), findsOneWidget);
      expect(find.text('250.000đ'), findsOneWidget);
      expect(find.text('1.000.000đ'), findsOneWidget);
    });

    testWidgets('formats whole-number percentage without decimals',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 2, 500000),
          _cell('Zalo', 'pickup', 2, 500000),
        ]),
      )));
      await tester.tap(_dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find
          .text(SharedLabels.todaySalesOrderBreakdownModeCountRevenueShare)
          .last);
      await tester.pumpAndSettle();
      // 50% (not "50.0%") for each source; 100% for the column total.
      expect(find.text('50%'), findsNWidgets(2));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('renders totals row with summed counts and revenue',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Tại tiệm - POS', 'pickup', 3, 900000),
          _cell('Tại tiệm - POS', 'delivery', 1, 300000),
          _cell('Zalo', 'pickup', 2, 500000),
        ]),
      )));
      // Totals row label.
      expect(find.text(SharedLabels.todaySalesOrderBreakdownTotal),
          findsOneWidget);
      // pickup-column total count = 3 + 2 = 5 (unique).
      expect(find.text('5'), findsOneWidget);
      // pickup-column total revenue = 900.000 + 500.000 = 1.400.000đ.
      expect(find.text('1.400.000đ'), findsOneWidget);
      // delivery-column total count = 1 (also appears in POS-delivery cell).
      expect(find.text('1'), findsNWidgets(2));
      // delivery-column total revenue = 300.000đ (also in POS-delivery cell).
      expect(find.text('300.000đ'), findsNWidgets(2));
    });

    testWidgets('orders sources by FR7 fixed priority then alphabetically',
        (tester) async {
      await tester.pumpWidget(_wrap(OrderBreakdownSection(
        breakdown: _breakdown([
          _cell('Zalo', 'pickup', 1, 100000),
          _cell('app', 'pickup', 1, 100000),
          _cell('Tại tiệm', 'pickup', 1, 100000),
          _cell('Tại tiệm - POS', 'pickup', 1, 100000),
          _cell('Facebook-DoanGia', 'pickup', 1, 100000),
          _cell('Facebook-Page-mới', 'pickup', 1, 100000),
          _cell('Điện thoại', 'pickup', 1, 100000),
          _cell('Amazon', 'pickup', 1, 100000),
        ]),
      )));
      // All priority sources render once.
      expect(find.text('Tại tiệm - POS'), findsOneWidget);
      expect(find.text('Tại tiệm'), findsOneWidget);
      expect(find.text('Facebook-DoanGia'), findsOneWidget);
      expect(find.text('Facebook-Page-mới'), findsOneWidget);
      expect(find.text('Zalo'), findsOneWidget);
      expect(find.text('Điện thoại'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
      // Unknown source "Amazon" sorts after the priority list alphabetically.
      expect(find.text('Amazon'), findsOneWidget);
    });
  });
}