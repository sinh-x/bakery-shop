import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/report_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/data/models/today_summary.dart';
import 'package:bakery_app/features/dashboard/management_dashboard_screen.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/orders.dart';

Order _order({
  required String ref,
  String status = 'new',
  String urgency = 'normal',
  String? dueDate,
  double totalPrice = 0,
  String customerName = 'Test',
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: customerName,
    status: status,
    urgency: urgency,
    dueDate: dueDate,
    totalPrice: totalPrice,
    items: const [],
    createdAt: DateTime(2026, 8, 5),
    updatedAt: DateTime(2026, 8, 5),
  );
}

class _FakeOrderService extends OrderService {
  _FakeOrderService() : super(Dio());
  List<Order> orders = const [];

  /// Orders returned for the day-scoped `due_date` call (dueDateOrdersProvider
  /// — CQ-1). Defaults to [orders] so tests that previously fed the today
  /// section via `summary.orders` keep working when they pass `orders:`.
  /// Tests that need to suppress the today-section rows (e.g. the
  /// critical-alert test, whose infinite pulse animation would otherwise
  /// stall `pumpAndSettle`) pass an explicit `dueDateOrders: const []`.
  List<Order> dueDateOrders = const [];

  @override
  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async {
    if (dueDate != null) return dueDateOrders;
    return orders;
  }

  @override
  Future<List<Order>> listActiveOrders({int limit = 200}) async => orders;
}

class _FakeReportService extends ReportService {
  _FakeReportService() : super(Dio());
  TodaySummary? summary;

  @override
  Future<TodaySummary> getTodaySummary({String? date}) async {
    return summary ??
        const TodaySummary(
          date: '2026-08-05',
          revenue: 0,
          orderCount: 0,
          cashTotal: 0,
          bankTransferTotal: 0,
          cashInTotal: 0,
          cashOutTotal: 0,
          orders: [],
        );
  }
}

class _FakeStockService extends StockService {
  _FakeStockService() : super(Dio());
  List<StockOverviewItem> items = const [];

  @override
  Future<List<StockOverviewItem>> getStockOverview() async => items;
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => 'http://test.local';
}

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  _FakeOrderPhotosNotifier() : super('unused');

  @override
  Future<List<OrderPhoto>> build() async => const [];
}

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/dashboard',
      builder: (_, _) => const ManagementDashboardScreen(),
    ),
    GoRoute(
      path: '/accounting',
      builder: (_, _) => const SizedBox(child: Text('accounting-page')),
    ),
    GoRoute(
      path: '/stock',
      builder: (_, _) => const SizedBox(child: Text('stock-page')),
    ),
    GoRoute(
      path: '/today-sales',
      builder: (_, _) => const SizedBox(child: Text('today-sales-page')),
    ),
  ],
  initialLocation: '/dashboard',
);

Future<void> _pump(
  WidgetTester tester, {
  List<Order> orders = const [],

  /// Orders returned by the separate `dueDateOrdersProvider` fetch (CQ-1).
  /// Defaults to [orders] so tests that feed the today-orders section via
  /// `orders:` keep working. Pass `const []` to suppress today-section
  /// rows (used by the critical-alert test to avoid the OrderCard pulse
  /// animation stalling `pumpAndSettle`).
  List<Order>? dueDateOrders,
  TodaySummary? summary,
  List<StockOverviewItem> stock = const [],
}) async {
  final orderService = _FakeOrderService()
    ..orders = orders
    ..dueDateOrders = dueDateOrders ?? orders;
  final reportService = _FakeReportService()..summary = summary;
  final stockService = _FakeStockService()..items = stock;
  final summaryOrders = summary?.orders ?? const <Order>[];
  final dueDateOrderList = dueDateOrders ?? orders;
  final allRefs = <String>{
    ...orders.map((o) => o.orderRef),
    ...summaryOrders.map((o) => o.orderRef),
    ...dueDateOrderList.map((o) => o.orderRef),
  };

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderServiceProvider.overrideWithValue(orderService),
        reportServiceProvider.overrideWithValue(reportService),
        stockServiceProvider.overrideWithValue(stockService),
        apiBaseUrlProvider.overrideWith(_FakeApiBaseUrlNotifier.new),
        for (final ref in allRefs)
          orderPhotosProvider(ref).overrideWith(_FakeOrderPhotosNotifier.new),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

TodaySummary _summary({
  double revenue = 0,
  int orderCount = 0,
  double cashTotal = 0,
  double bankTransferTotal = 0,
  double cashInTotal = 0,
  double cashOutTotal = 0,
  List<Order> orders = const [],
}) {
  return TodaySummary(
    date: '2026-08-05',
    revenue: revenue,
    orderCount: orderCount,
    cashTotal: cashTotal,
    bankTransferTotal: bankTransferTotal,
    cashInTotal: cashInTotal,
    cashOutTotal: cashOutTotal,
    orders: orders,
  );
}

void main() {
  testWidgets(
    'renders app bar, section titles, and the Xem doanh số hôm nay entry card',
    (tester) async {
      await _pump(tester);
      expect(find.text(SharedLabels.tabManagement), findsOneWidget);
      expect(find.text(SharedLabels.dashboardSectionMetrics), findsOneWidget);
      expect(
        find.text(SharedLabels.dashboardMetricViewTodaySales),
        findsOneWidget,
      );
      expect(find.text(SharedLabels.dashboardSectionShortcuts), findsOneWidget);
      await tester.dragUntilVisible(
        find.text(SharedLabels.dashboardSectionAlerts),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(find.text(SharedLabels.dashboardSectionAlerts), findsOneWidget);
    },
  );

  testWidgets('renders six shortcut tiles including Tiền tại quầy', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(SharedLabels.dashboardShortcutStock), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCategories), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCustomers), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutExpenses), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump();
    expect(find.text(SharedLabels.dashboardShortcutBlanks), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCashDrawer), findsOneWidget);
  });

  testWidgets('Xem doanh số hôm nay card tap navigates to /today-sales', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text(SharedLabels.dashboardMetricViewTodaySales));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('today-sales-page'), findsOneWidget);
  });

  testWidgets('shortcut tap navigates via go router', (tester) async {
    await _pump(tester);
    await tester.tap(
      find.text(SharedLabels.dashboardShortcutStock),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('stock-page'), findsOneWidget);
  });

  testWidgets('accounting menu navigates to accounting', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Kế toán'), findsWidgets);
    await tester.tap(find.text('Kế toán').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('accounting-page'), findsOneWidget);
  });

  testWidgets('refresh button is present', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  // Phase 3 — real API wiring (FR2/FR4/AC2/AC3). DG-376: metrics now come
  // from the today-summary API (single source of truth).
  // Note: The individual order-count and low-stock MetricCards were replaced
  // by DG-374's single "Xem doanh số hôm nay" entry-point card. The
  // underlying providers remain covered by dashboard_metrics_provider_test.dart
  // and today_order_list_test.dart.
  testWidgets(
    'revenue-today metric comes from API summary only (Bug 3 — no double-count)',
    (tester) async {
      await _pump(
        tester,
        summary: _summary(
          revenue: 175000,
          orderCount: 2,
          orders: [
            _order(ref: 'A', dueDate: '2026-08-05', totalPrice: 50000),
            _order(ref: 'B', dueDate: '2026-08-05', totalPrice: 25000),
          ],
        ),
      );
      // 175000 (API journal-only) — NOT 250000 (old double-count behavior).
      expect(find.text('175.000đ'), findsOneWidget);
    },
  );

  testWidgets(
    'critical-order alert banner shows when urgency=critical (FR5/AC9)',
    (tester) async {
      await _pump(
        tester,
        orders: [
          _order(ref: 'A', urgency: 'critical'),
          _order(ref: 'B', urgency: 'critical'),
          _order(ref: 'C', urgency: 'normal'),
        ],
        // Suppress today-section rows so the critical OrderCards' pulse
        // animation does not stall `pumpAndSettle` (CQ-1 — the today section
        // now fetches its rows separately).
        dueDateOrders: const [],
      );
      await tester.dragUntilVisible(
        find.byIcon(Icons.warning_amber_rounded),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        find.text(SharedLabels.dashboardCriticalOrdersAlert(2)),
        findsOneWidget,
      );
    },
  );

  testWidgets('no critical alert banner when no critical orders (FR5/AC9)', (
    tester,
  ) async {
    await _pump(
      tester,
      orders: [_order(ref: 'A', urgency: 'normal')],
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  // DG-376 Phase 5/6 — Today's orders section (FR6/AC6). CQ-1: the order
  // rows now come from a separate dueDateOrdersProvider fetch (not
  // summary.orders), so the orders are injected via the OrderService fake.
  testWidgets('today orders section groups orders by status with a count '
      '(FR6/AC6)', (tester) async {
    await _pump(
      tester,
      summary: _summary(orderCount: 4),
      orders: [
        _order(ref: 'A', status: 'new', customerName: 'An'),
        _order(ref: 'B', status: 'new', customerName: 'Bình'),
        _order(ref: 'C', status: 'completed', customerName: 'Cúc'),
        _order(ref: 'D', status: 'cancelled', customerName: 'Dung'),
      ],
    );
    // Scroll the today-orders section into view (it sits below metrics +
    // shortcuts).
    await tester.dragUntilVisible(
      find.text('An'),
      find.byType(Scrollable).first,
      const Offset(0, -500),
    );
    // Section title renders.
    expect(find.text(SharedLabels.todayOrders), findsOneWidget);
    // Status group headers (some may be off-screen, so use findWidgets).
    expect(find.text(OrdersLabels.statusNew), findsWidgets);
    expect(find.text(OrdersLabels.statusCompleted), findsWidgets);
    expect(find.text(OrdersLabels.statusCancelled), findsWidgets);
    // Order rows render.
    expect(find.text('An'), findsOneWidget);
    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('Cúc'), findsOneWidget);
    expect(find.text('Dung'), findsOneWidget);
  });

  testWidgets('today orders section shows empty state when no orders (FR6)', (
    tester,
  ) async {
    await _pump(tester, summary: _summary(orderCount: 0), orders: const []);
    await tester.dragUntilVisible(
      find.text(SharedLabels.khongCoDonHomNay),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    expect(find.text(SharedLabels.todayOrders), findsOneWidget);
    expect(find.text(SharedLabels.khongCoDonHomNay), findsOneWidget);
  });

  // CQ-1: the order rows must render from the separate dueDateOrdersProvider
  // fetch, NOT from summary.orders. This test passes orders only via the
  // dueDateOrdersProvider fake (summary.orders and the active order list are
  // both empty) and asserts the rows still appear — proving the section no
  // longer reads summary.orders.
  testWidgets('today orders section renders rows from the separate order '
      'fetch, not summary.orders (CQ-1)', (tester) async {
    await _pump(
      tester,
      // Summary carries NO orders (mirrors the new backend shape where the
      // orders list was removed in DG-409 Phase 1).
      summary: _summary(orderCount: 3, orders: const []),
      // The active order list is empty — the rows below come ONLY from the
      // separate due-date fetch.
      orders: const [],
      dueDateOrders: [
        _order(ref: 'SEP-1', status: 'new', customerName: 'Riêng-A'),
        _order(ref: 'SEP-2', status: 'completed', customerName: 'Riêng-B'),
        _order(ref: 'SEP-3', status: 'cancelled', customerName: 'Riêng-C'),
      ],
    );
    await tester.dragUntilVisible(
      find.text('Riêng-A'),
      find.byType(Scrollable).first,
      const Offset(0, -500),
    );
    // The rows from the separate fetch render even though summary.orders
    // and the active order list were both empty.
    expect(find.text('Riêng-A'), findsOneWidget);
    expect(find.text('Riêng-B'), findsOneWidget);
    expect(find.text('Riêng-C'), findsOneWidget);
  });
}
