import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/work_item_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_payment_status_summary.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_work_item_summary.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WorkItemsInterceptor extends Interceptor {
  _WorkItemsInterceptor(this._items);

  final List<Map<String, dynamic>> _items;

  @override
  void onRequest(options, handler) {
    if (options.path == '/api/orders/ORD-1/items') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _items,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

Order _order({double totalPrice = 750000}) => Order.fromJson({
      'id': '1',
      'orderRef': 'ORD-1',
      'status': 'new',
      'customerName': 'KH A',
      'customerPhone': '',
      'dueDate': null,
      'dueTime': '10:00',
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
    });

void main() {
  testWidgets('OrderWorkItemSummary renders count and status distribution',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(
        _WorkItemsInterceptor([
          {'id': '1', 'orderId': '1', 'productName': 'Bánh A', 'status': 'delivered'},
          {'id': '2', 'orderId': '1', 'productName': 'Bánh B', 'status': 'delivered'},
          {'id': '3', 'orderId': '1', 'productName': 'Bánh C', 'status': 'working'},
        ]),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sharedPreferencesProvider.overrideWithValue(prefs),
          orderServiceProvider.overrideWithValue(OrderService(dio)),
          workItemServiceProvider.overrideWithValue(WorkItemService(dio)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OrderWorkItemSummary(orderRef: 'ORD-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.workItemSummaryTitle), findsOneWidget);
    expect(find.text(VN.workItemSummaryCount(3)), findsOneWidget);
    expect(
      find.textContaining('2 ${VN.workItemDelivered}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 ${VN.workItemWorking}'),
      findsOneWidget,
    );
  });

  testWidgets('OrderWorkItemSummary renders empty state when no items',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(
        _WorkItemsInterceptor(const <Map<String, dynamic>>[]),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          sharedPreferencesProvider.overrideWithValue(prefs),
          orderServiceProvider.overrideWithValue(OrderService(dio)),
          workItemServiceProvider.overrideWithValue(WorkItemService(dio)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OrderWorkItemSummary(orderRef: 'ORD-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.workItemSummaryEmpty), findsOneWidget);
  });

  testWidgets('OrderPaymentStatusSummary renders paid vs total', (tester) async {
    final order = _order(totalPrice: 750000);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderPaymentStatusSummary(
            order: order,
            amountPaid: 500000,
            paymentColor: Colors.orange,
          ),
        ),
      ),
    );
    expect(find.text(VN.paymentStatusSummaryTitle), findsOneWidget);
    expect(find.text(VN.paid), findsOneWidget);
    expect(find.textContaining('500.000'), findsOneWidget);
    expect(find.textContaining('750.000'), findsOneWidget);
  });
}