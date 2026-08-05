import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/data/api/accounting_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/journal_entry.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/dashboard/management_dashboard_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';

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

class _FakeAccountingService extends AccountingService {
  _FakeAccountingService() : super(Dio());
  List<JournalEntry> entries = const [];

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
    return JournalListResponse(total: entries.length, items: entries);
  }
}

class _FakeStockService extends StockService {
  _FakeStockService() : super(Dio());
  List<StockOverviewItem> items = const [];

  @override
  Future<List<StockOverviewItem>> getStockOverview() async => items;
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
      ],
      initialLocation: '/dashboard',
    );

Future<void> _pump(
  WidgetTester tester, {
  List<Order> orders = const [],
  List<JournalEntry> journal = const [],
  List<StockOverviewItem> stock = const [],
}) async {
  final orderService = _FakeOrderService()..orders = orders;
  final accountingService = _FakeAccountingService()..entries = journal;
  final stockService = _FakeStockService()..items = stock;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderServiceProvider.overrideWithValue(orderService),
        accountingServiceProvider.overrideWithValue(accountingService),
        stockServiceProvider.overrideWithValue(stockService),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
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

StockOverviewItem _stockItem(String name, int qty) {
  return StockOverviewItem(
    productId: 1,
    productName: name,
    category: 'Bánh',
    quantity: qty,
    basePrice: null,
    // totalQuantity folds perChip quantities, so route qty through one option
    // to make the item's total equal qty.
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

  testWidgets('renders app bar, section titles, and three metric cards',
      (tester) async {
    await _pump(tester);
    expect(find.text(SharedLabels.tabManagement), findsOneWidget);
    expect(find.text('Chỉ số hôm nay'), findsOneWidget);
    expect(find.text('Truy cập nhanh'), findsOneWidget);
    expect(find.text('Đơn hàng hôm nay'), findsOneWidget);
    expect(find.text('Doanh thu hôm nay'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Tồn kho thấp'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('Tồn kho thấp'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Cảnh báo'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('Cảnh báo'), findsOneWidget);
  });

  testWidgets('renders five shortcut tiles', (tester) async {
    await _pump(tester);
    expect(find.text('Kho hàng'), findsOneWidget);
    expect(find.text('Quản lý danh mục'), findsOneWidget);
    expect(find.text('Quản lý khách hàng'), findsOneWidget);
    expect(find.text('Chi phí'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump();
    expect(find.text('Quản lý phôi bánh'), findsOneWidget);
  });

  testWidgets('shortcut tap navigates via go router', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Kho hàng'), warnIfMissed: false);
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

  // Phase 3 — real API wiring (FR2/FR4/AC2/AC3).
  testWidgets('orders-today metric reflects real order count (FR2/AC2)',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(ref: 'A', dueDate: todayStr),
        _order(ref: 'B', dueDate: todayStr),
        _order(ref: 'C', dueDate: '2026-08-06'),
      ],
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets(
      'revenue-today metric combines journal 4100 credits + orders totalPrice (FR4/AC3)',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(ref: 'A', dueDate: todayStr, totalPrice: 50000),
        _order(ref: 'B', dueDate: todayStr, totalPrice: 25000),
      ],
      journal: [_journalEntryWithCredit(100000, '4100')],
    );
    // 100000 (journal) + 75000 (orders) = 175000đ
    expect(find.text('175.000đ'), findsOneWidget);
  });

  testWidgets('low-stock metric counts items at or below threshold (FR2/AC3)',
      (tester) async {
    await _pump(
      tester,
      stock: [
        _stockItem('Bánh mì', 3),
        _stockItem('Bánh bao', 5),
        _stockItem('Bánh kem', 20),
      ],
    );
    await tester.dragUntilVisible(
      find.text('Tồn kho thấp'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    // Two items (3 and 5) are ≤ lowStockThreshold (5).
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('critical-order alert banner shows when urgency=critical (FR5/AC9)',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(ref: 'A', urgency: 'critical'),
        _order(ref: 'B', urgency: 'critical'),
        _order(ref: 'C', urgency: 'normal'),
      ],
    );
    await tester.dragUntilVisible(
      find.byIcon(Icons.warning_amber_rounded),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Có 2 đơn hàng khẩn cấp cần xử lý'), findsOneWidget);
  });

  testWidgets('no critical alert banner when no critical orders (FR5/AC9)',
      (tester) async {
    await _pump(
      tester,
      orders: [_order(ref: 'A', urgency: 'normal')],
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}