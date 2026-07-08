import 'dart:convert';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/orders/order_edit_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage_summary_card.dart';
import 'package:bakery_app/providers/config_provider.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captured PATCH /api/orders/{ref} body (the save call).
Map<String, dynamic>? _savedOrderBody;
String? _savedCustomerName;
String? _savedCustomerId;
bool _createCustomerCalled = false;
String? _createdCustomerName;
String? _createdCustomerPhone;

Map<String, dynamic> _orderJson({
  String customerName = '',
  String customerPhone = '',
  String deliveryPhone = '',
  int? customerId,
  String deliveryType = 'pickup',
  String publicOrderCode = '',
}) {
  return {
    'id': 'order-1',
    'orderRef': 'REF-1',
    'publicOrderCode': publicOrderCode,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'deliveryPhone': deliveryPhone,
    'customerId': customerId,
    'items': <Map<String, dynamic>>[],
    'totalPrice': 0.0,
    'status': 'new',
    'deliveryType': deliveryType,
    'deliveryAddress': '',
    'shippingFee': 0.0,
    'notes': '',
    'source': '',
    'packingChecklist': <Map<String, dynamic>>[],
    'createdAt': '2026-07-01T08:00:00Z',
    'updatedAt': '2026-07-01T08:00:00Z',
  };
}

class _EditSaveInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    // GET /api/orders/{ref} — order detail.
    if (path == '/api/orders/REF-1' && options.method == 'GET') {
      handler.resolve(
        Response(
            requestOptions: options,
            statusCode: 200,
            data: _orderJson()),
      );
      return;
    }

    // GET /api/orders/{ref}/items — work items (empty list).
    if (path.startsWith('/api/orders/REF-1/items') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    // GET /api/orders/{ref}/photos — order photos (empty list).
    if (path.startsWith('/api/orders/REF-1/photos') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    // GET /api/orders — order list refresh after save.
    if (path == '/api/orders' && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    // POST /api/customers — auto-create-customer (FR1).
    if (path == '/api/customers' && options.method == 'POST') {
      _createCustomerCalled = true;
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
      _createdCustomerName = body['name'] as String?;
      _createdCustomerPhone = body['phone'] as String?;
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 201,
          data: {
            'id': 42,
            'name': _createdCustomerName ?? '',
            'phone': _createdCustomerPhone ?? '',
            'sharedPhoneCustomers': <Map<String, dynamic>>[],
          },
        ),
      );
      return;
    }

    // PATCH /api/orders/{ref} — edit save.
    if (path == '/api/orders/REF-1' && options.method == 'PATCH') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
      _savedOrderBody = body;
      _savedCustomerName = body['customerName'] as String?;
      _savedCustomerId = body['customerId']?.toString();
      final updated = _orderJson(
        customerName: _savedCustomerName ?? '',
        customerId: int.tryParse(_savedCustomerId ?? ''),
      );
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: updated),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}

class _FixedConfigNotifier extends ConfigValuesNotifier {
  final List<String> _values;
  _FixedConfigNotifier(this._values) : super('test');

  @override
  Future<List<String>> build() async => _values;
}

Future<Widget> _buildScreenFor(String orderRef, Interceptor interceptor) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..interceptors.add(interceptor);

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dioProvider.overrideWithValue(dio),
    loggedByProvider.overrideWith(() => _LoggedByFixed('staff')),
    orderSourcesProvider.overrideWith(() => _FixedConfigNotifier(<String>['Tại tiệm'])),
    shippingFeeBusProvider.overrideWith(() => _FixedConfigNotifier(<String>['25000'])),
    shippingFeeDoorProvider.overrideWith(() => _FixedConfigNotifier(<String>['20000'])),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/edit/$orderRef',
    routes: [
      GoRoute(
        path: '/edit/:ref',
        builder: (context, state) =>
            OrderEditScreen(orderRef: state.pathParameters['ref']!),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      routerConfig: router,
    ),
  );
}

Future<Widget> _buildScreen() => _buildScreenFor('REF-1', _EditSaveInterceptor());

Future<Widget> _buildScreenForSources(String orderRef, Interceptor interceptor) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..interceptors.add(interceptor);

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dioProvider.overrideWithValue(dio),
    loggedByProvider.overrideWith(() => _LoggedByFixed('staff')),
    orderSourcesProvider.overrideWith(() => _FixedConfigNotifier(<String>[
      OrdersLabels.sourceFbDoangia,
      OrdersLabels.sourceFbPageMoi,
      OrdersLabels.sourceZalo,
      OrdersLabels.sourceDienThoai,
      OrdersLabels.sourceTaiTiem,
    ])),
    shippingFeeBusProvider.overrideWith(() => _FixedConfigNotifier(<String>['25000'])),
    shippingFeeDoorProvider.overrideWith(() => _FixedConfigNotifier(<String>['20000'])),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/edit/$orderRef',
    routes: [
      GoRoute(
        path: '/edit/:ref',
        builder: (context, state) =>
            OrderEditScreen(orderRef: state.pathParameters['ref']!),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      routerConfig: router,
    ),
  );
}

class _LoggedByFixed extends LoggedByNotifier {
  final String _name;
  _LoggedByFixed(this._name);

  @override
  String build() => _name;
}

void main() {
  setUp(() {
    _savedOrderBody = null;
    _savedCustomerName = null;
    _savedCustomerId = null;
    _createCustomerCalled = false;
    _createdCustomerName = null;
    _createdCustomerPhone = null;
  });

  testWidgets(
      'AC1: edit save with name+phone but no linked customer auto-creates and links a customer',
      (tester) async {
    await tester.pumpWidget(await _buildScreen());
    await tester.pumpAndSettle();

    // Stage 1 → continue to Stage 2.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    // Enter customer name and phone (no customer linked).
    await tester.enterText(
      find.ancestor(
        of: find.text('Tên khách hàng'),
        matching: find.byType(TextField),
      ),
      'Nguyễn Văn A',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Số điện thoại'),
        matching: find.byType(TextField),
      ),
      '0901234567',
    );

    // Continue through Stage 3 to Stage 4.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    // Save.
    await tester.tap(find.descendant(
      of: find.byType(FilledButton),
      matching: find.text('Lưu'),
    ));
    await tester.pumpAndSettle();

    expect(_createCustomerCalled, isTrue,
        reason: 'FR1: should auto-create a customer when name+phone present and no customer linked');
    expect(_createdCustomerName, 'Nguyễn Văn A');
    // PhoneInputFormatter formats 10 digits as xxxx-xxx-xxx.
    expect(_createdCustomerPhone, '0901-234-567');
    expect(_savedOrderBody, isNotNull);
    expect(_savedOrderBody!['customerId'], 42,
        reason: 'AC1: auto-created customer id (42) should be linked to the order');
  });

  testWidgets(
      "AC2: edit save with empty customer name persists 'Khách lẻ' default and does not block",
      (tester) async {
    await tester.pumpWidget(await _buildScreen());
    await tester.pumpAndSettle();

    // Navigate directly to Stage 4 without entering a name.
    // Stage 1 → Stage 2 → Stage 3 → Stage 4.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    // Leave name empty. Enter a phone so save still has a phone (FR2 only
    // governs the name default; phone is independent).
    await tester.enterText(
      find.ancestor(
        of: find.text('Số điện thoại'),
        matching: find.byType(TextField),
      ),
      '0987654321',
    );
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    // Save should succeed — no validation blocks it.
    await tester.tap(find.descendant(
      of: find.byType(FilledButton),
      matching: find.text('Lưu'),
    ));
    await tester.pumpAndSettle();

    expect(_savedOrderBody, isNotNull,
        reason: 'AC2: save should proceed with empty name (no validation blocking)');
    expect(_savedCustomerName, 'Khách lẻ',
        reason: "AC2: empty name should default to 'Khách lẻ' at save");
    // With empty name but phone present, FR1 auto-create would fire too —
    // but the name is empty so the guard `name.trim().isNotEmpty` blocks it.
    // The Khách lẻ default is applied AFTER the auto-create check, so no
    // customer is created here.
    expect(_createCustomerCalled, isFalse,
        reason: 'FR1 guard requires non-empty name; empty name should not trigger auto-create');
  });

  testWidgets(
      'AC2: edit save with empty name and no phone succeeds (no blocking)',
      (tester) async {
    await tester.pumpWidget(await _buildScreen());
    await tester.pumpAndSettle();

    // Navigate to Stage 4 with both name and phone empty.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(FilledButton),
      matching: find.text('Lưu'),
    ));
    await tester.pumpAndSettle();

    expect(_savedOrderBody, isNotNull,
        reason: 'Save must succeed with empty name and phone — no validation blocking');
    expect(_savedCustomerName, 'Khách lẻ');
    expect(_createCustomerCalled, isFalse,
        reason: 'No name+phone → no auto-create');
  });

  testWidgets(
      'AC7: edit Stage 3 prefills delivery phone from customer phone for bus/door when empty',
      (tester) async {
    await tester.pumpWidget(await _buildScreenFor('REF-PREFILL', _PrefillInterceptor()));
    await tester.pumpAndSettle();

    // Navigate to Stage 3 (delivery).
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    // The delivery phone field should be prefilled from the customer phone.
    final deliveryPhoneField = tester.widget<TextField>(
      find.ancestor(
        of: find.text('SĐT nhận hàng'),
        matching: find.byType(TextField),
      ),
    );
    expect(deliveryPhoneField.controller?.text ?? '', '0912000111',
        reason: 'AC7: delivery phone should be prefilled from customer phone on init for bus');

    // Select door delivery — should keep the prefilled value (not overwrite
    // since the field is no longer empty).
    await tester.tap(find.text('Giao tận nơi'));
    await tester.pumpAndSettle();
    expect(deliveryPhoneField.controller?.text ?? '', '0912000111',
        reason: 'AC7: switching to door must not overwrite an already-prefilled value');
  });

  testWidgets(
      'AC6: edit Stage 2 source selector renders in create grouped two-row layout',
      (tester) async {
    await tester.pumpWidget(await _buildScreenForSources(
        'REF-SRC', _AllSourcesInterceptor()));
    await tester.pumpAndSettle();

    // Navigate to Stage 2.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    // Row 1 chips (Facebook sources) should be present.
    expect(find.text(OrdersLabels.sourceFbDoangia), findsOneWidget);
    expect(find.text(OrdersLabels.sourceFbPageMoi), findsOneWidget);
    // Row 2 chips should be present.
    expect(find.text(OrdersLabels.sourceZalo), findsOneWidget);
    expect(find.text(OrdersLabels.sourceDienThoai), findsOneWidget);
    expect(find.text(OrdersLabels.sourceTaiTiem), findsOneWidget);
  });

  testWidgets(
      'AC8: edit Stage 2 shows Customer summary card alongside Product card',
      (tester) async {
    await tester.pumpWidget(await _buildScreenForSources(
        'REF-SRC', _AllSourcesInterceptor()));
    await tester.pumpAndSettle();

    // Navigate to Stage 2.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductSummaryCard), findsWidgets,
        reason: 'Stage 2 should show the Product summary card');
    expect(find.byType(CustomerSummaryCard), findsOneWidget,
        reason: 'AC8: Stage 2 should show the Customer summary card');
  });

  testWidgets(
      'AC8: edit Stage 3 shows Product, Customer, and Delivery summary cards',
      (tester) async {
    await tester.pumpWidget(await _buildScreenForSources(
        'REF-SRC', _AllSourcesInterceptor()));
    await tester.pumpAndSettle();

    // Navigate to Stage 3.
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductSummaryCard), findsWidgets,
        reason: 'Stage 3 should show the Product summary card');
    expect(find.byType(CustomerSummaryCard), findsOneWidget,
        reason: 'AC8: Stage 3 should show the Customer summary card');
    expect(find.byType(DeliverySummaryCard), findsOneWidget,
        reason: 'AC8: Stage 3 should show the Delivery summary card');
  });
}

/// Interceptor variant for the prefill test — returns a bus-delivery order
/// with a customer phone but an empty delivery phone.
class _PrefillInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    if (path == '/api/orders/REF-PREFILL' && options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'order-2',
            'orderRef': 'REF-PREFILL',
            'publicOrderCode': '',
            'customerName': '',
            'customerPhone': '0912000111',
            'deliveryPhone': '',
            'customerId': null,
            'items': <Map<String, dynamic>>[],
            'totalPrice': 0.0,
            'status': 'new',
            'deliveryType': 'bus',
            'deliveryAddress': '',
            'shippingFee': 25000.0,
            'notes': '',
            'source': '',
            'packingChecklist': <Map<String, dynamic>>[],
            'createdAt': '2026-07-01T08:00:00Z',
            'updatedAt': '2026-07-01T08:00:00Z',
          },
        ),
      );
      return;
    }

    if (path.startsWith('/api/orders/REF-PREFILL/items') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path.startsWith('/api/orders/REF-PREFILL/photos') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path == '/api/orders' && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path == '/api/orders/REF-PREFILL' && options.method == 'PATCH') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'order-2',
            'orderRef': 'REF-PREFILL',
            'publicOrderCode': '',
            'customerName': '',
            'customerPhone': '0912000111',
            'deliveryPhone': '',
            'customerId': null,
            'items': <Map<String, dynamic>>[],
            'totalPrice': 0.0,
            'status': 'new',
            'deliveryType': 'bus',
            'deliveryAddress': '',
            'shippingFee': 25000.0,
            'notes': '',
            'source': '',
            'packingChecklist': <Map<String, dynamic>>[],
            'createdAt': '2026-07-01T08:00:00Z',
            'updatedAt': '2026-07-01T08:00:00Z',
          },
        ),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}

/// Interceptor that returns all five order sources for source-selector tests.
class _AllSourcesInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    if (path == '/api/orders/REF-SRC' && options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'order-src',
            'orderRef': 'REF-SRC',
            'publicOrderCode': '',
            'customerName': '',
            'customerPhone': '',
            'deliveryPhone': '',
            'customerId': null,
            'items': <Map<String, dynamic>>[],
            'totalPrice': 0.0,
            'status': 'new',
            'deliveryType': 'pickup',
            'deliveryAddress': '',
            'shippingFee': 0.0,
            'notes': '',
            'source': '',
            'packingChecklist': <Map<String, dynamic>>[],
            'createdAt': '2026-07-01T08:00:00Z',
            'updatedAt': '2026-07-01T08:00:00Z',
          },
        ),
      );
      return;
    }

    if (path.startsWith('/api/orders/REF-SRC/items') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path.startsWith('/api/orders/REF-SRC/photos') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path == '/api/products' && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path.startsWith('/api/products') && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path == '/api/orders' && options.method == 'GET') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]),
      );
      return;
    }

    if (path == '/api/orders/REF-SRC' && options.method == 'PATCH') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'order-src',
            'orderRef': 'REF-SRC',
            'publicOrderCode': '',
            'customerName': '',
            'customerPhone': '',
            'deliveryPhone': '',
            'customerId': null,
            'items': <Map<String, dynamic>>[],
            'totalPrice': 0.0,
            'status': 'new',
            'deliveryType': 'pickup',
            'deliveryAddress': '',
            'shippingFee': 0.0,
            'notes': '',
            'source': '',
            'packingChecklist': <Map<String, dynamic>>[],
            'createdAt': '2026-07-01T08:00:00Z',
            'updatedAt': '2026-07-01T08:00:00Z',
          },
        ),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}