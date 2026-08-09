import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/report_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/today_summary.dart';
import 'package:bakery_app/providers/dashboard/dashboard_metrics_provider.dart';

Order _order({
  required String ref,
  String status = 'new',
  String urgency = 'normal',
  String? dueDate,
  double totalPrice = 0,
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: 'Test',
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

  @override
  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async => orders;

  @override
  Future<List<Order>> listActiveOrders({int limit = 200}) async => orders;
}

class _FakeReportService extends ReportService {
  _FakeReportService() : super(Dio());
  TodaySummary? summary;
  int getTodaySummaryCalls = 0;

  @override
  Future<TodaySummary> getTodaySummary({String? date}) async {
    getTodaySummaryCalls++;
    return summary ??
        const TodaySummary(
          date: '2026-08-05',
          revenue: 0,
          orderCount: 0,
          cashTotal: 0,
          bankTransferTotal: 0,
          orders: [],
        );
  }
}

class _FakeStockService extends StockService {
  _FakeStockService() : super(Dio());
  List<StockOverviewItem> items = const [];
  int getStockOverviewCalls = 0;

  @override
  Future<List<StockOverviewItem>> getStockOverview() async {
    getStockOverviewCalls++;
    return items;
  }
}

StockOverviewItem _stockItem(int qty) {
  return StockOverviewItem(
    productId: 1,
    productName: 'Bánh',
    category: 'Bánh',
    quantity: qty,
    basePrice: null,
    perChip: [
      StockOverviewOption(
        normalizedPrice: 0,
        quantity: qty,
        chipLabels: const [],
        chipLabel: null,
      ),
    ],
  );
}

TodaySummary _summary({
  double revenue = 0,
  int orderCount = 0,
  double cashTotal = 0,
  double bankTransferTotal = 0,
  List<Order> orders = const [],
}) {
  return TodaySummary(
    date: '2026-08-05',
    revenue: revenue,
    orderCount: orderCount,
    cashTotal: cashTotal,
    bankTransferTotal: bankTransferTotal,
    orders: orders,
  );
}

void main() {
  group('dashboard_metrics_provider pure helpers', () {
    test('countCriticalOrders counts only urgency=critical', () {
      final orders = [
        _order(ref: 'A', urgency: 'critical'),
        _order(ref: 'B', urgency: 'critical'),
        _order(ref: 'C', urgency: 'urgent'),
        _order(ref: 'D', urgency: 'normal'),
      ];
      expect(countCriticalOrders(orders), 2);
    });
  });

  group('dashboardRevenueStockProvider', () {
    test('fires today-summary + stock calls in parallel (NFR3)', () async {
      final reports = _FakeReportService()
        ..summary = _summary(
          revenue: 100000,
          orderCount: 4,
          orders: [_order(ref: 'A'), _order(ref: 'B')],
        );
      final stock = _FakeStockService()..items = [_stockItem(3), _stockItem(20)];
      final orders = _FakeOrderService()..orders = const [];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        reportServiceProvider.overrideWithValue(reports),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(dashboardRevenueStockProvider.future);

      // Both parallel calls fired exactly once each.
      expect(reports.getTodaySummaryCalls, 1);
      expect(stock.getStockOverviewCalls, 1);

      // Revenue comes from the API summary (journal 4100 only — no
      // totalPrice double-count), order count from the API (all statuses).
      expect(result.revenueToday, 100000);
      expect(result.orderCount, 4);
      // Only one stock item (qty 3) is ≤ lowStockThreshold (5).
      expect(result.lowStockCount, 1);
    });

    test('revenue comes from API summary only (Bug 3 — no double-count)',
        () async {
      // The API returns revenue = 250000 (journal 4100 credits). Even though
      // orders carry totalPrice, the provider must NOT add it (Bug 3 fix).
      final reports = _FakeReportService()
        ..summary = _summary(
          revenue: 250000,
          orderCount: 2,
          orders: [
            _order(ref: 'A', dueDate: '2026-08-05', totalPrice: 30000),
            _order(ref: 'B', dueDate: '2026-08-05', totalPrice: 20000),
          ],
        );
      final stock = _FakeStockService()..items = const [];
      final orders = _FakeOrderService()..orders = const [];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        reportServiceProvider.overrideWithValue(reports),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(dashboardRevenueStockProvider.future);

      // 250000 (API journal-only) — NOT 300000 (old double-count behavior).
      expect(result.revenueToday, 250000);
      expect(result.orderCount, 2);
    });

    test('order count includes completed POS orders (Bug 1)', () async {
      // The API counts all orders due today regardless of status. The provider
      // surfaces that count directly; it no longer filters the active order
      // list client-side (which excluded completed POS orders).
      final reports = _FakeReportService()
        ..summary = _summary(
          orderCount: 5,
          orders: [
            _order(ref: 'POS1', status: 'completed'),
            _order(ref: 'POS2', status: 'completed'),
            _order(ref: 'A', status: 'new'),
            _order(ref: 'B', status: 'delivered'),
            _order(ref: 'C', status: 'cancelled'),
          ],
        );
      final stock = _FakeStockService()..items = const [];
      final orders = _FakeOrderService()..orders = const [];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        reportServiceProvider.overrideWithValue(reports),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(dashboardRevenueStockProvider.future);

      expect(result.orderCount, 5);
    });
  });

  group('todaySummaryProvider', () {
    test('returns the API today-summary unchanged', () async {
      final reports = _FakeReportService()
        ..summary = _summary(
          revenue: 320000,
          orderCount: 7,
          cashTotal: 150000,
          bankTransferTotal: 170000,
          orders: [_order(ref: 'A'), _order(ref: 'B')],
        );

      final container = ProviderContainer(overrides: [
        reportServiceProvider.overrideWithValue(reports),
      ]);
      addTearDown(container.dispose);

      final summary = await container.read(todaySummaryProvider.future);

      expect(summary.revenue, 320000);
      expect(summary.orderCount, 7);
      expect(summary.cashTotal, 150000);
      expect(summary.bankTransferTotal, 170000);
      expect(summary.orders.length, 2);
    });
  });
}