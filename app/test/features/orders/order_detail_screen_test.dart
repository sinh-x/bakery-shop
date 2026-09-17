import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/features/orders/order_detail_screen.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Interceptor serving the order-detail endpoint and related sub-resources.
class _OrderDetailInterceptor extends Interceptor {
  _OrderDetailInterceptor(this._order, {this.fail = false});

  final Map<String, dynamic>? _order;
  final bool fail;
  int inventoryAuditRequests = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Order detail: GET /api/orders/{ref}
    if (options.path == '/api/orders/ORD-1') {
      if (fail) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
        return;
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _order,
        ),
      );
      return;
    }
    // Inventory audit: GET /api/orders/{ref}/inventory-audit
    if (options.path == '/api/orders/ORD-1/inventory-audit') {
      inventoryAuditRequests++;
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const <String, dynamic>{
            'items': <dynamic>[],
            'total': 0,
            'hasMore': false,
            'limit': 100,
            'offset': 0,
          },
        ),
      );
      return;
    }
    // Order photos: GET /api/orders/{ref}/photos
    if (options.path == '/api/orders/ORD-1/photos') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const <dynamic>[],
        ),
      );
      return;
    }
    // Work items: GET /api/orders/{ref}/work-items
    if (options.path == '/api/orders/ORD-1/work-items') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const <dynamic>[],
        ),
      );
      return;
    }
    // Payment transactions: GET /api/orders/{ref}/payments
    if (options.path == '/api/orders/ORD-1/payments') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const <dynamic>[],
        ),
      );
      return;
    }
    // Acknowledge: POST /api/orders/{ref}/acknowledge
    if (options.path == '/api/orders/ORD-1/acknowledge') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _order,
        ),
      );
      return;
    }
    // Customer detail: GET /api/customers/{id}
    if (RegExp(r'^/api/customers/\d+$').hasMatch(options.path) &&
        options.method == 'GET') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 42,
            'name': 'Nguyễn Văn B',
            'phone': '0901234567',
            'phones': <Map<String, dynamic>>[
              {'phone': '0901234567', 'isPrimary': true},
            ],
            'createdAt': '2026-01-01T00:00:00Z',
            'sharedPhoneCustomers': <Map<String, dynamic>>[],
          },
        ),
      );
      return;
    }
    // Customer orders: GET /api/customers/{id}/orders
    if (RegExp(r'^/api/customers/\d+/orders$').hasMatch(options.path) &&
        options.method == 'GET') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <dynamic>[
            {
              'id': '100',
              'orderRef': 'ORD-100',
              'customerName': 'Nguyễn Văn B',
              'items': <Map<String, dynamic>>[],
              'totalPrice': 150000.0,
              'status': 'completed',
              'createdAt': '2026-06-01T08:00:00Z',
              'updatedAt': '2026-06-01T08:00:00Z',
            },
          ],
        ),
      );
      return;
    }
    handler.next(options);
  }
}

Map<String, dynamic> _orderJson({
  String status = 'new',
  String customerName = 'KH A',
  double totalPrice = 200000,
  String? dueDate,
  String dueTime = '10:00',
  int? customerId,
}) {
  return {
    'id': '1',
    'orderRef': 'ORD-1',
    'status': status,
    'customerName': customerName,
    'customerPhone': '',
    'customerId': customerId,
    'dueDate': dueDate,
    'dueTime': dueTime,
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'items': <Map<String, dynamic>>[
      {
        'productId': 'p',
        'productName': 'Bánh kem',
        'quantity': 1,
        'unitPrice': totalPrice,
      },
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
    'createdAt': '2026-07-15T08:00:00Z',
    'updatedAt': '2026-07-15T08:00:00Z',
    'completeness': 'complete',
    'missingFields': <String>[],
  };
}

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/orders/:ref',
      builder: (_, state) =>
          OrderDetailScreen(orderRef: state.pathParameters['ref']!),
    ),
    GoRoute(
      path: '/orders/:ref/edit',
      builder: (_, state) =>
          SizedBox(child: Text('edit-${state.pathParameters['ref']}')),
    ),
  ],
  initialLocation: '/orders/ORD-1',
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
  testWidgets('renders app bar with order-detail title', (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    expect(find.text(OrdersLabels.orderDetail), findsOneWidget);
  });

  testWidgets('renders edit and print app bar actions when data loaded', (
    tester,
  ) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    // Edit icon appears in app bar and possibly in the body.
    expect(find.byIcon(Icons.edit_outlined), findsAtLeast(1));
    expect(find.byIcon(Icons.print_outlined), findsAtLeast(1));
  });

  testWidgets('renders error state with retry when API fails', (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(null, fail: true));
    expect(find.text(SharedLabels.apiError), findsOneWidget);
    expect(find.text(SharedLabels.retry), findsOneWidget);
  });

  testWidgets('overflow menu shows add-incident and google-maps items', (
    tester,
  ) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(EventsLabels.addOrderIncident), findsOneWidget);
    expect(find.text(OrdersLabels.googleMapsContextMenuLabel), findsOneWidget);
  });

  testWidgets('edit button navigates to edit route', (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('edit-ORD-1'), findsOneWidget);
  });

  testWidgets('renders customer name in body when data loaded', (tester) async {
    await _pump(
      tester,
      interceptor: _OrderDetailInterceptor(
        _orderJson(customerName: 'Nguyễn Văn A'),
      ),
    );
    expect(find.text('Nguyễn Văn A', skipOffstage: false), findsOneWidget);
  });

  testWidgets('renders order status banner when data loaded', (tester) async {
    await _pump(
      tester,
      interceptor: _OrderDetailInterceptor(_orderJson(status: 'confirmed')),
    );
    // The status banner shows the Vietnamese status label.
    expect(
      find.text(OrdersLabels.statusConfirmed, skipOffstage: false),
      findsAtLeast(1),
    );
  });

  testWidgets('renders five scrollable tabs and lazily loads inventory audit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final interceptor = _OrderDetailInterceptor(_orderJson());
    await _pump(tester, interceptor: interceptor);

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(find.byType(Tab), findsNWidgets(5));
    expect(find.text(StockLabels.inventoryReviewTab), findsOneWidget);
    expect(interceptor.inventoryAuditRequests, 0);

    tabBar.controller!.animateTo(4);
    await tester.pumpAndSettle();
    expect(interceptor.inventoryAuditRequests, 1);
    expect(find.text(StockLabels.inventoryAuditEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer tab shows empty state when customerId is null (AC8)', (
    tester,
  ) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    tester.widget<TabBar>(find.byType(TabBar)).controller!.animateTo(3);
    await tester.pumpAndSettle();
    expect(find.text(OrdersLabels.orderDetailCustomerEmpty), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });

  testWidgets(
    'customer tab shows customer info and history when customerId present (AC7)',
    (tester) async {
      await _pump(
        tester,
        interceptor: _OrderDetailInterceptor(_orderJson(customerId: 42)),
      );
      tester.widget<TabBar>(find.byType(TabBar)).controller!.animateTo(3);
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Văn B'), findsAtLeast(1));
      expect(find.textContaining('0901234567'), findsAtLeast(1));
      // Historical order rendered via OrderCard shows its orderRef.
      expect(find.text('ORD-100'), findsOneWidget);
    },
  );
}
