import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/orders/order_history_screen.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _orderJson({
  required String id,
  required String orderRef,
  required String customerName,
  required String customerPhone,
  String status = 'new',
}) {
  return {
    'id': id,
    'orderRef': orderRef,
    'status': status,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'dueDate': '2026-05-18',
    'dueTime': null,
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'items': [],
    'totalPrice': 100000.0,
    'amountPaid': 0.0,
    'isPaid': false,
    'notes': '',
    'source': '',
    'packingChecklist': [],
    'shippingFee': 0.0,
    'workTicketPrintedAt': null,
    'createdBy': '',
    'createdAt': '2026-05-18T08:00:00',
    'updatedAt': '2026-05-18T08:00:00',
  };
}

class _OrderHistoryInterceptor extends Interceptor {
  _OrderHistoryInterceptor({
    required this.orders,
  });

  final List<Map<String, dynamic>> orders;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders') {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: orders),
      );
      return;
    }

    if (options.path.startsWith('/api/orders/') && options.path.endsWith('/photos')) {
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: const []),
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

Future<Widget> _buildScreen({
  required List<Map<String, dynamic>> orders,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio()
    ..interceptors.add(
      _OrderHistoryInterceptor(
        orders: orders,
      ),
    );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      orderServiceProvider.overrideWithValue(OrderService(dio)),
    ],
    child: const MaterialApp(home: OrderHistoryScreen()),
  );
}

void main() {
  testWidgets('renders default history data and status sections', (tester) async {
    await tester.pumpWidget(
      await _buildScreen(
        orders: [
          _orderJson(
            id: '1',
            orderRef: 'ORD-001',
            customerName: 'Nguyen Van A',
            customerPhone: '0900000001',
            status: 'new',
          ),
          _orderJson(
            id: '2',
            orderRef: 'ORD-002',
            customerName: 'Tran Thi B',
            customerPhone: '0900000002',
            status: 'delivered',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nguyen Van A'), findsOneWidget);
    expect(find.text('Tran Thi B'), findsOneWidget);
    expect(find.text(VN.statusNew), findsOneWidget);
    expect(find.text(VN.statusDelivered), findsOneWidget);
  });

  testWidgets('search filters orders and shows not-found empty state', (tester) async {
    await tester.pumpWidget(
      await _buildScreen(
        orders: [
          _orderJson(
            id: '1',
            orderRef: 'ORD-001',
            customerName: 'Nguyen Van A',
            customerPhone: '0900000001',
          ),
          _orderJson(
            id: '2',
            orderRef: 'ORD-002',
            customerName: 'Tran Thi B',
            customerPhone: '0900000002',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0900000002');
    await tester.pumpAndSettle();
    expect(find.text('Tran Thi B'), findsOneWidget);
    expect(find.text('Nguyen Van A'), findsNothing);

    await tester.enterText(find.byType(TextField), 'not-found');
    await tester.pumpAndSettle();
    expect(find.text(VN.lichSuDonHangKhongTimThay), findsOneWidget);
  });

  testWidgets('shows empty state when no history items', (tester) async {
    await tester.pumpWidget(await _buildScreen(orders: const []));
    await tester.pumpAndSettle();

    expect(find.text(VN.lichSuDonHangTrong), findsOneWidget);
  });

  testWidgets('supports switching between single-day and range modes', (tester) async {
    await tester.pumpWidget(await _buildScreen(orders: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.lichSuDonHangLocMotNgay));
    await tester.pumpAndSettle();
    var singleChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, VN.lichSuDonHangLocMotNgay),
    );
    expect(singleChip.selected, isTrue);

    await tester.tap(find.text(VN.lichSuDonHangLocKhoangNgay));
    await tester.pumpAndSettle();
    singleChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, VN.lichSuDonHangLocMotNgay),
    );
    expect(singleChip.selected, isFalse);
  });
}
