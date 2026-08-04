import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_transaction_list.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio interceptor that serves a fixed transaction page for a single drawer
/// id. Captures the request path so tests can assert on the wiring.
class _TxnInterceptor extends Interceptor {
  _TxnInterceptor({
    required this.total,
    required this.items,
  });

  final int total;
  final List<Map<String, dynamic>> items;

  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastQuery = options.queryParameters;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': total,
          'limit': options.queryParameters['limit'] ?? 50,
          'offset': options.queryParameters['offset'] ?? 0,
          'items': items,
        },
      ),
    );
  }
}

Map<String, dynamic> _txn({
  String id = '1',
  String type = 'cash_drawer_open',
  int amount = 1000000,
  String timestamp = '2026-08-01T08:00:00Z',
  String note = '',
}) =>
    {
      'id': id,
      'type': type,
      'amount': amount,
      'timestamp': timestamp,
      'note': note,
    };

ProviderContainer _containerWith(Interceptor interceptor) => ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(interceptor),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, Widget widget,
    {required ProviderContainer container}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: widget),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CashDrawerTransactionList (DG-343 Phase 3)', () {
    testWidgets(
        'AC1/AC3: renders each transaction with type label, signed amount, '
        'timestamp, and note', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 3,
        items: [
          _txn(
              id: '1',
              type: 'cash_drawer_open',
              amount: 1000000,
              note: 'Mở quầy sáng'),
          _txn(
              id: '2',
              type: 'payment_transaction',
              amount: 50000,
              note: 'Bán bánh mì'),
          _txn(
              id: '3',
              type: 'cash_drawer_cash_out',
              amount: -200000,
              note: 'Rút tiền chủ'),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 7, poll: false),
        container: container,
      );

      // AC3: short type labels are rendered.
      expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
      // AC1: timestamps rendered via formatDisplay (dd/MM/yyyy HH:mm).
      expect(find.textContaining('01/08/2026'), findsNWidgets(3));
      // AC1: notes render when present.
      expect(find.text('Mở quầy sáng'), findsOneWidget);
      expect(find.text('Bán bánh mì'), findsOneWidget);
      expect(find.text('Rút tiền chủ'), findsOneWidget);
      // The request hit the right endpoint.
      expect(interceptor.lastPath, '/api/cash-drawer/7/transactions');
    });

    testWidgets(
        'AC5: inflow amounts show "+" prefix in green, outflow amounts show '
        '"-" prefix in red', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 2,
        items: [
          _txn(id: '1', type: 'payment_transaction', amount: 75000),
          _txn(id: '2', type: 'cash_drawer_cash_out', amount: -300000),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // AC5: inflow row shows "+75.000đ" in green, outflow row shows
      // "-300.000đ" in red. We assert the text is present and that the
      // TextStyle color matches the expected palette.
      final inflowFinder = find.text('+75.000đ');
      final outflowFinder = find.text('-300.000đ');
      expect(inflowFinder, findsOneWidget,
          reason: 'inflow amount should be prefixed with "+"');
      expect(outflowFinder, findsOneWidget,
          reason: 'outflow amount should be prefixed with "-"');

      final inflowText = tester.widget<Text>(inflowFinder);
      expect(inflowText.style?.color, Colors.green.shade700,
          reason: 'inflow amount should be green');

      final errorColor =
          Theme.of(tester.element(find.byType(MaterialApp))).colorScheme.error;
      final outflowText = tester.widget<Text>(outflowFinder);
      expect(outflowText.style?.color, errorColor,
          reason: 'outflow amount should be red');
    });

    testWidgets(
        'AC2/FR4: scroll near the bottom loads the next page (infinite '
        'scroll)', (tester) async {
      // Two pages: 50 items on the first page, 10 on the second, total 60.
      final firstPage = List.generate(
          50, (i) => _txn(id: '${i + 1}', type: 'payment_transaction'));
      final secondPage = List.generate(
          10, (i) => _txn(id: '${i + 51}', type: 'expense', amount: -1000));

      final interceptor = _PagedTxnInterceptor(
        pages: [firstPage, secondPage],
        total: 60,
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 9, poll: false),
        container: container,
      );

      // First page loaded — sale-type rows are visible (ListView.builder is
      // lazy, so only the visible rows are built). The first page request
      // hit offset 0.
      expect(interceptor.requests.length, 1);
      expect(interceptor.requests.last['offset'], 0);
      expect(find.text(VN.cashDrawerTxnTypeSale), findsWidgets);
      // No expense-type rows yet (second page not loaded).
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsNothing);

      // Scroll to the bottom to trigger infinite-scroll load of page 2.
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();

      // Second page loaded — expense rows now appear.
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsWidgets);
      expect(interceptor.requests.length, greaterThanOrEqualTo(2));
      // The second request used offset=50.
      expect(interceptor.requests.last['offset'], 50);
    });

    testWidgets(
        'shows an empty state when the drawer has no transactions',
        (tester) async {
      final interceptor = _TxnInterceptor(total: 0, items: const []);
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 2, poll: false),
        container: container,
      );

      // Empty state surfaces the tab label as a hint.
      expect(find.text(VN.cashDrawerTransactionsTab), findsOneWidget);
    });
  });
}

/// Multi-page interceptor: returns each page in sequence based on the
/// requested offset. Records every request so tests can assert on the
/// pagination wiring. Pages are 50 items wide; the request offset / 50
/// selects the page index.
class _PagedTxnInterceptor extends Interceptor {
  _PagedTxnInterceptor({required this.pages, required this.total});

  final List<List<Map<String, dynamic>>> pages;
  final int total;
  final List<Map<String, dynamic>> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final offset = (options.queryParameters['offset'] as int?) ?? 0;
    requests.add({'offset': offset, 'limit': options.queryParameters['limit']});
    final pageIndex = offset ~/ 50;
    final page =
        pageIndex < pages.length ? pages[pageIndex] : const <Map<String, dynamic>>[];
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': total,
          'limit': options.queryParameters['limit'] ?? 50,
          'offset': offset,
          'items': page,
        },
      ),
    );
  }
}