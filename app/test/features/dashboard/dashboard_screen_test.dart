import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/features/dashboard/dashboard_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves the dashboard active-orders list endpoint and records query params.
class _DashboardInterceptor extends Interceptor {
  _DashboardInterceptor(this._orders, {this.fail = false});

  final List<Map<String, dynamic>> _orders;
  final bool fail;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.startsWith('/api/orders/') &&
        options.path.endsWith('/photos')) {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const <dynamic>[],
        ),
      );
      return;
    }
    if (options.path != '/api/orders') {
      handler.next(options);
      return;
    }
    if (fail) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    final activeOnly =
        (options.queryParameters['active_only'] as bool?) ?? false;
    final list = activeOnly
        ? _orders
            .where((o) =>
                !const ['completed', 'cancelled'].contains(o['status']))
            .toList()
        : _orders;
    handler.resolve(
      Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: list,
      ),
    );
  }
}

Map<String, dynamic> _orderJson({
  required String id,
  required String orderRef,
  required String customerName,
  String status = 'new',
  String? dueDate,
  double totalPrice = 100000,
}) {
  return {
    'id': id,
    'orderRef': orderRef,
    'status': status,
    'customerName': customerName,
    'customerPhone': '',
    'dueDate': dueDate,
    'dueTime': null,
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'items': <Map<String, dynamic>>[
      {'productId': 'p', 'productName': 'Bánh', 'quantity': 1, 'unitPrice': totalPrice},
    ],
    'totalPrice': totalPrice,
    'amountPaid': 0.0,
    'isPaid': false,
    'notes': '',
    'source': '',
    'packingChecklist': <dynamic>[],
    'shippingFee': 0.0,
    'workTicketPrintedAt': null,
    'createdBy': '',
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
    'completeness': 'complete',
    'missingFields': <String>[],
  };
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/accounting',
          builder: (_, _) => const SizedBox(child: Text('accounting-page')),
        ),
      ],
      initialLocation: '/dashboard',
    );

Future<void> _pump(
  WidgetTester tester, {
  required Interceptor interceptor,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(prefs),
        orderServiceProvider.overrideWithValue(OrderService(dio)),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders app bar with dashboard title and refresh button',
      (tester) async {
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(const []),
    );
    expect(find.text(VN.tabDashboard), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('shows empty-state message when no active orders', (tester) async {
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(const []),
    );
    expect(find.text('Không có đơn hàng sắp đến hạn'), findsOneWidget);
    expect(find.text('Không có đơn hàng đang xử lý'), findsOneWidget);
  });

  testWidgets('renders overdue + today + upcoming sections', (tester) async {
    final today = DateTime.now();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final todayStr = fmt(today);
    final in3 = fmt(today.add(const Duration(days: 2)));
    final orders = [
      _orderJson(
        id: '1',
        orderRef: 'ORD-1',
        customerName: 'Overdue KH',
        status: 'new',
        dueDate: '2020-01-01',
      ),
      _orderJson(
        id: '2',
        orderRef: 'ORD-2',
        customerName: 'Today KH',
        status: 'confirmed',
        dueDate: todayStr,
        totalPrice: 200000,
      ),
      _orderJson(
        id: '3',
        orderRef: 'ORD-3',
        customerName: 'Upcoming KH',
        status: 'in_progress',
        dueDate: in3,
        totalPrice: 50000,
      ),
    ];
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(orders),
    );
    expect(find.text(VN.overdueOrders), findsOneWidget);
    expect(find.text(VN.todayOrders), findsOneWidget);
    expect(find.text(VN.upcomingDue), findsOneWidget);
    expect(find.text('Overdue KH', skipOffstage: false), findsOneWidget);
    expect(find.text('Today KH', skipOffstage: false), findsOneWidget);
    expect(find.text('Upcoming KH', skipOffstage: false), findsOneWidget);
  });

  testWidgets('renders error state with retry button when API fails',
      (tester) async {
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(const [], fail: true),
    );
    expect(find.text(VN.apiError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });

  testWidgets('refresh button invalidates the dashboard provider',
      (tester) async {
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(const []),
    );
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    // Refresh triggers provider invalidation and reload; empty state remains.
    expect(find.text('Không có đơn hàng sắp đến hạn'), findsOneWidget);
  });

  testWidgets('overflow menu can navigate to accounting', (tester) async {
    await _pump(
      tester,
      interceptor: _DashboardInterceptor(const []),
    );
    // Open the overflow menu and tap the accounting item.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(VN.accountingTitle), findsOneWidget);
    await tester.tap(find.text(VN.accountingTitle));
    await tester.pumpAndSettle();
    expect(find.text('accounting-page'), findsOneWidget);
  });
}