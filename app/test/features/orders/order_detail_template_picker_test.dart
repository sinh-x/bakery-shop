import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/features/orders/order_detail_screen.dart';
import 'package:bakery_app/features/templates/widgets/template_picker_modal.dart';
import 'package:bakery_app/shared/providers/logged_by_provider.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration test for the order detail screen's template picker overflow
/// menu item (DG-375 Phase 4.3 / AC1).
///
/// Verifies the "Mẫu tin nhắn" menu item appears in the overflow menu and
/// opens the [TemplatePickerModal] when tapped.

Map<String, dynamic> _orderJson() => {
      'id': '1',
      'orderRef': 'ORD-1',
      'publicOrderCode': 'DG-1',
      'status': 'new',
      'customerName': 'KH A',
      'customerPhone': '0901',
      'customerId': null,
      'dueDate': '2026-08-15',
      'dueTime': '14:00',
      'deliveryType': 'pickup',
      'deliveryAddress': '',
      'items': <Map<String, dynamic>>[
        {'productId': 'p', 'productName': 'Bánh kem', 'quantity': 1, 'unitPrice': 200000},
      ],
      'totalPrice': 200000.0,
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

class _Interceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders/ORD-1' && options.method == 'GET') {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options, statusCode: 200, data: _orderJson(),
      ));
      return;
    }
    if (options.path == '/api/orders/ORD-1/photos') {
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options, statusCode: 200, data: const <dynamic>[],
      ));
      return;
    }
    if (options.path == '/api/orders/ORD-1/work-items') {
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options, statusCode: 200, data: const <dynamic>[],
      ));
      return;
    }
    if (options.path == '/api/orders/ORD-1/payments') {
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options, statusCode: 200, data: const <dynamic>[],
      ));
      return;
    }
    if (options.path == '/api/orders/ORD-1/acknowledge') {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options, statusCode: 200, data: _orderJson(),
      ));
      return;
    }
    // Templates list endpoint — returns one template so the modal renders
    // content when opened from the overflow menu.
    if (options.path == '/api/templates' && options.method == 'GET') {
      handler.resolve(Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <Map<String, dynamic>>[
          {
            'id': 1,
            'scenario': 'ask_info',
            'name': 'Mẫu hỏi thông tin',
            'body': 'Dạ mình đặt bánh khi nào lấy ạ?',
            'is_system': true,
            'sort_order': 1,
            'active': true,
            'created_at': '2026-08-10T00:00:00Z',
            'updated_at': '2026-08-10T00:00:00Z',
          },
        ],
      ));
      return;
    }
    handler.next(options);
  }
}

class _LoggedByFixed extends LoggedByNotifier {
  @override
  String build() => 'Staff';
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/orders/:ref',
          builder: (_, state) =>
              OrderDetailScreen(orderRef: state.pathParameters['ref']!),
        ),
      ],
      initialLocation: '/orders/ORD-1',
    );

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(_Interceptor());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(prefs),
        orderServiceProvider.overrideWithValue(OrderService(dio)),
        loggedByProvider.overrideWith(_LoggedByFixed.new),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Order detail template picker integration (AC1)', () {
    testWidgets('overflow menu shows the "Mẫu tin nhắn" item', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.overflowMenuOpenPicker), findsOneWidget);
    });

    testWidgets('tapping "Mẫu tin nhắn" opens the template picker modal',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TemplatesLabels.overflowMenuOpenPicker));
      await tester.pumpAndSettle();
      expect(find.byType(TemplatePickerModal), findsOneWidget);
      expect(find.text(TemplatesLabels.pickerTitle), findsOneWidget);
      // The scenario header for ask_info is rendered.
      expect(find.text(TemplatesLabels.scenarioAskInfo), findsOneWidget);
      // The ask_info template name appears (the only template returned by
      // the fake list endpoint).
      expect(find.text('Mẫu hỏi thông tin'), findsOneWidget);
    });
  });
}