import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/data/api/accounting_service.dart';
import 'package:bakery_app/data/api/cash_drawer_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/cash_drawer.dart';
import 'package:bakery_app/data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/data/models/journal_entry.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_breakdown_card.dart';
import 'package:bakery_app/features/today_sales/today_sales_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';

Order _order({
  required String ref,
  String status = 'new',
  String? dueDate,
  double totalPrice = 0,
  bool isPaid = false,
  double amountPaid = 0,
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: 'Khách $ref',
    status: status,
    dueDate: dueDate,
    totalPrice: totalPrice,
    isPaid: isPaid,
    amountPaid: amountPaid,
    items: const [],
    createdAt: DateTime(2026, 8, 8),
    updatedAt: DateTime(2026, 8, 8),
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

class _FakeCashDrawerService extends CashDrawerService {
  _FakeCashDrawerService() : super(Dio());
  CashDrawer? activeDrawer;
  List<CashDrawerTransaction> transactions = const [];

  @override
  Future<CashDrawer?> getDrawerStatus() async => activeDrawer;

  @override
  Future<CashDrawerTransactionResponse> getDrawerTransactions(
    int drawerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return CashDrawerTransactionResponse(
      total: transactions.length,
      limit: limit,
      offset: offset,
      items: transactions,
    );
  }
}

JournalLine _line(String accountCode, double debit, double credit) =>
    JournalLine(
      id: 'l-$accountCode-$debit-$credit',
      journalEntryId: 'e0',
      accountId: accountCode,
      debit: debit,
      credit: credit,
      accountCode: accountCode,
    );

JournalEntry _entry(List<JournalLine> lines) => JournalEntry(
      id: 'e0',
      description: 'test',
      lines: lines,
      createdAt: DateTime(2026, 8, 8),
    );

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/today-sales',
          builder: (_, _) => const TodaySalesScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const SizedBox(child: Text('dashboard-page')),
        ),
      ],
      initialLocation: '/today-sales',
    );

Future<void> _pump(
  WidgetTester tester, {
  List<Order> orders = const [],
  List<JournalEntry> journal = const [],
  List<StockOverviewItem> stock = const [],
  CashDrawer? activeDrawer,
  List<CashDrawerTransaction> drawerTransactions = const [],
}) async {
  final orderService = _FakeOrderService()..orders = orders;
  final accountingService = _FakeAccountingService()..entries = journal;
  final stockService = _FakeStockService()..items = stock;
  final cashDrawerService = _FakeCashDrawerService()
    ..activeDrawer = activeDrawer
    ..transactions = drawerTransactions;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderServiceProvider.overrideWithValue(orderService),
        accountingServiceProvider.overrideWithValue(accountingService),
        stockServiceProvider.overrideWithValue(stockService),
        cashDrawerServiceProvider.overrideWithValue(cashDrawerService),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

String get _today {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets(
      'renders app bar title and revenue summary section headers (AC5)',
      (tester) async {
    await _pump(
      tester,
      orders: [_order(ref: 'A', dueDate: _today, totalPrice: 100000)],
      journal: [
        _entry([
          _line('4100', 0, 100000),
          _line('1101', 60000, 0),
          _line('1210', 40000, 0),
        ]),
      ],
    );
    expect(find.text(SharedLabels.todaySalesTitle), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesRevenueSection), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesTotalRevenue), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesOrderCount), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesCashTotal), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesBankTransferTotal), findsOneWidget);
  });

  testWidgets('shows today order list with order ref, customer, status, '
      'total price, and payment status (AC6)', (tester) async {
    await _pump(
      tester,
      orders: [
        _order(
          ref: 'ORD-1',
          dueDate: _today,
          status: 'confirmed',
          totalPrice: 250000,
          isPaid: true,
        ),
      ],
    );
    await tester.dragUntilVisible(
      find.text('ORD-1'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('ORD-1'), findsOneWidget);
    expect(find.text('Khách ORD-1'), findsOneWidget);
    expect(find.text('250.000đ'), findsWidgets);
    expect(find.text(VN.paid), findsOneWidget);
    expect(find.text(SharedLabels.todaySalesOrderListSection), findsOneWidget);
  });

  testWidgets('filters out orders not due today (only today orders in list)',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(ref: 'TODAY', dueDate: _today, totalPrice: 50000),
        _order(ref: 'YESTERDAY', dueDate: '2026-01-01', totalPrice: 999999),
      ],
    );
    await tester.dragUntilVisible(
      find.text('TODAY'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsNothing);
  });

  testWidgets('shows empty orders message when no orders due today',
      (tester) async {
    await _pump(tester);
    await tester.dragUntilVisible(
      find.text(SharedLabels.todaySalesEmptyOrders),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text(SharedLabels.todaySalesEmptyOrders), findsOneWidget);
  });

  testWidgets('shows partial paid badge for amountPaid > 0 and not isPaid',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(
          ref: 'PART',
          dueDate: _today,
          totalPrice: 200000,
          amountPaid: 50000,
        ),
      ],
    );
    await tester.dragUntilVisible(
      find.text(VN.partialPaid),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text(VN.partialPaid), findsOneWidget);
  });

  testWidgets('shows unpaid badge for amountPaid == 0 and not isPaid',
      (tester) async {
    await _pump(
      tester,
      orders: [
        _order(ref: 'UNPAID', dueDate: _today, totalPrice: 100000),
      ],
    );
    await tester.dragUntilVisible(
      find.text(VN.unpaid),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text(VN.unpaid), findsOneWidget);
  });

  testWidgets('refresh button is present', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  // DG-374 Phase 3 / AC7: active drawer → cashflow breakdown card renders.
  testWidgets(
      'shows cashflow breakdown card with all 8 categories when an active '
      'drawer exists (AC7)', (tester) async {
    await _pump(
      tester,
      activeDrawer: const CashDrawer(
        id: '1',
        status: 'open',
        openingBalance: 1000000,
        expectedBalance: 1250000,
      ),
      drawerTransactions: [
        const CashDrawerTransaction(
          id: '1',
          type: 'cash_drawer_open',
          amount: 1000000,
        ),
        const CashDrawerTransaction(
          id: '2',
          type: 'payment_transaction',
          amount: 50000,
        ),
        const CashDrawerTransaction(
          id: '3',
          type: 'cash_drawer_cash_out',
          amount: -200000,
        ),
      ],
    );
    await tester.dragUntilVisible(
      find.text(SharedLabels.todaySalesCashflowSection),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    expect(find.text(SharedLabels.todaySalesCashflowSection), findsOneWidget);
    // The breakdown card renders all 8 category labels.
    expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeRefund), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeExpense), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeCashIn), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeClose), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeBusShipping), findsOneWidget);
    expect(find.byType(CashDrawerBreakdownCard), findsOneWidget);
  });

  // DG-374 Phase 3 / AC8: no active drawer → placeholder message.
  testWidgets(
      'shows "Chưa mở quầy hôm nay" placeholder when no active drawer '
      '(AC8)', (tester) async {
    await _pump(tester, activeDrawer: null);
    await tester.dragUntilVisible(
      find.text(SharedLabels.todaySalesNoActiveDrawer),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    expect(find.text(SharedLabels.todaySalesNoActiveDrawer), findsOneWidget);
    // The breakdown card must not render when there is no active drawer.
    expect(find.byType(CashDrawerBreakdownCard), findsNothing);
  });
}