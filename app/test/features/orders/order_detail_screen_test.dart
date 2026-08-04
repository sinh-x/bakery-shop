import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/features/orders/order_detail_screen.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interceptor serving the order-detail endpoint and related sub-resources.
class _OrderDetailInterceptor extends Interceptor {
  _OrderDetailInterceptor(this._order, {this.fail = false});

  final Map<String, dynamic>? _order;
  final bool fail;

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
    handler.next(options);
  }
}

Map<String, dynamic> _orderJson({
  String status = 'new',
  String customerName = 'KH A',
  double totalPrice = 200000,
  String? dueDate,
  String dueTime = '10:00',
}) {
  return {
    'id': '1',
    'orderRef': 'ORD-1',
    'status': status,
    'customerName': customerName,
    'customerPhone': '',
    'dueDate': dueDate,
    'dueTime': dueTime,
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'items': <Map<String, dynamic>>[
      {'productId': 'p', 'productName': 'Bánh kem', 'quantity': 1, 'unitPrice': totalPrice},
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
    expect(find.text(VN.orderDetail), findsOneWidget);
  });

  testWidgets('renders edit and print app bar actions when data loaded',
      (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    // Edit icon appears in app bar and possibly in the body.
    expect(find.byIcon(Icons.edit_outlined), findsAtLeast(1));
    expect(find.byIcon(Icons.print_outlined), findsAtLeast(1));
  });

  testWidgets('renders error state with retry when API fails', (tester) async {
    await _pump(
      tester,
      interceptor: _OrderDetailInterceptor(null, fail: true),
    );
    expect(find.text(VN.apiError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });

  testWidgets('overflow menu shows add-incident and google-maps items',
      (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(VN.addOrderIncident), findsOneWidget);
    expect(find.text(OrdersLabels.googleMapsContextMenuLabel), findsOneWidget);
  });

  testWidgets('edit button navigates to edit route', (tester) async {
    await _pump(tester, interceptor: _OrderDetailInterceptor(_orderJson()));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('edit-ORD-1'), findsOneWidget);
  });

  testWidgets('renders customer name in body when data loaded',
      (tester) async {
    await _pump(
      tester,
      interceptor:
          _OrderDetailInterceptor(_orderJson(customerName: 'Nguyễn Văn A')),
    );
    expect(find.text('Nguyễn Văn A', skipOffstage: false), findsOneWidget);
  });

  testWidgets('renders order status banner when data loaded', (tester) async {
    await _pump(
      tester,
      interceptor: _OrderDetailInterceptor(_orderJson(status: 'confirmed')),
    );
    // The status banner shows the Vietnamese status label.
    expect(find.text(VN.statusConfirmed, skipOffstage: false), findsAtLeast(1));
  });
}