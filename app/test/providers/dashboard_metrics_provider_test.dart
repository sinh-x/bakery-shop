import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/accounting_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/journal_entry.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/providers/dashboard/dashboard_metrics_provider.dart';
import 'package:bakery_app/providers/order/order_list_providers.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';

Order _order({
  required String ref,
  String urgency = 'normal',
  String? dueDate,
  double totalPrice = 0,
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: 'Test',
    status: 'new',
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

class _FakeAccountingService extends AccountingService {
  _FakeAccountingService() : super(Dio());
  List<JournalEntry> entries = const [];
  int listJournalCalls = 0;

  @override
  Future<JournalListResponse> listJournal({
    String? since,
    String? until,
    int? accountId,
    String? sourceType,
    int? sourceId,
    int limit = 100,
    int offset = 0,
  }) async {
    listJournalCalls++;
    return JournalListResponse(total: entries.length, items: entries);
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

JournalEntry _journalEntryWithCredit(double credit, String accountCode) {
  return JournalEntry(
    id: 'j1',
    lines: [
      JournalLine(
        id: 'l1',
        journalEntryId: 'j1',
        accountId: accountCode,
        accountCode: accountCode,
        credit: credit,
      ),
    ],
    createdAt: DateTime(2026, 8, 5),
  );
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

void main() {
  final todayStr = formatApiDate(DateTime(2026, 8, 5));

  group('dashboard_metrics_provider pure helpers', () {
    test('countOrdersToday counts only orders with dueDate == today', () {
      final orders = [
        _order(ref: 'A', dueDate: todayStr),
        _order(ref: 'B', dueDate: todayStr),
        _order(ref: 'C', dueDate: '2026-08-06'),
        _order(ref: 'D'),
      ];
      expect(countOrdersToday(orders), 2);
    });

    test('countCriticalOrders counts only urgency=critical', () {
      final orders = [
        _order(ref: 'A', urgency: 'critical'),
        _order(ref: 'B', urgency: 'critical'),
        _order(ref: 'C', urgency: 'urgent'),
        _order(ref: 'D', urgency: 'normal'),
      ];
      expect(countCriticalOrders(orders), 2);
    });

    test('sumOrdersRevenueToday sums totalPrice for today orders', () {
      final orders = [
        _order(ref: 'A', dueDate: todayStr, totalPrice: 50000),
        _order(ref: 'B', dueDate: todayStr, totalPrice: 25000),
        _order(ref: 'C', dueDate: '2026-08-06', totalPrice: 999999),
      ];
      expect(sumOrdersRevenueToday(orders), 75000);
    });
  });

  group('dashboardRevenueStockProvider', () {
    test('fires journal + stock calls in parallel (FR4/NFR2)', () async {
      final accounting = _FakeAccountingService()
        ..entries = [_journalEntryWithCredit(100000, '4100')];
      final stock = _FakeStockService()..items = [_stockItem(3), _stockItem(20)];
      final orders = _FakeOrderService()
        ..orders = [_order(ref: 'A', dueDate: todayStr, totalPrice: 50000)];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        accountingServiceProvider.overrideWithValue(accounting),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      // Prime orderListProvider so the revenue provider can read its value.
      await container.read(orderListProvider.future);
      final result = await container.read(dashboardRevenueStockProvider.future);

      // Both parallel calls fired exactly once each.
      expect(accounting.listJournalCalls, 1);
      expect(stock.getStockOverviewCalls, 1);

      // Revenue = journal 100000 + orders 50000 = 150000.
      expect(result.revenueToday, 150000);
      // Only one stock item (qty 3) is ≤ lowStockThreshold (5).
      expect(result.lowStockCount, 1);
    });

    test('combines journal 4100 credits with orders totalPrice (FR4/AC3)',
        () async {
      final accounting = _FakeAccountingService()
        ..entries = [
          _journalEntryWithCredit(200000, '4100'),
          _journalEntryWithCredit(50000, '4100'),
        ];
      final stock = _FakeStockService()..items = const [];
      final orders = _FakeOrderService()
        ..orders = [
          _order(ref: 'A', dueDate: todayStr, totalPrice: 30000),
          _order(ref: 'B', dueDate: todayStr, totalPrice: 20000),
        ];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        accountingServiceProvider.overrideWithValue(accounting),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final result = await container.read(dashboardRevenueStockProvider.future);

      // 250000 (journal) + 50000 (orders) = 300000.
      expect(result.revenueToday, 300000);
    });

    test('ignores journal lines for non-revenue accounts', () async {
      final accounting = _FakeAccountingService()
        ..entries = [
          _journalEntryWithCredit(100000, '4100'),
          _journalEntryWithCredit(999999, '1101'),
        ];
      final stock = _FakeStockService()..items = const [];
      final orders = _FakeOrderService()..orders = const [];

      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(orders),
        accountingServiceProvider.overrideWithValue(accounting),
        stockServiceProvider.overrideWithValue(stock),
      ]);
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final result = await container.read(dashboardRevenueStockProvider.future);

      expect(result.revenueToday, 100000);
    });
  });
}