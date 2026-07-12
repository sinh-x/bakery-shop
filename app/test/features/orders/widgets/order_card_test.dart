import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_item.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_card.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';

const _testRef = 'TEST-ORDER-1';

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  final List<OrderPhoto> _photos;
  _FakeOrderPhotosNotifier(this._photos) : super(_testRef);

  @override
  Future<List<OrderPhoto>> build() async => _photos;
}

Order _completeOrder() => Order(
  id: '1',
  orderRef: _testRef,
  customerName: 'Nguyễn Văn A',
  items: const [
    OrderItem(
      productId: 'prod-1',
      productName: 'Bánh kem',
      quantity: 1,
      unitPrice: 200000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 200000.0,
  status: 'new',
  dueDate: '2026-07-15',
  dueTime: '10:00',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'complete',
  missingFields: const [],
);

Order _incompleteOrder() => Order(
  id: '2',
  orderRef: _testRef,
  customerName: 'Khách',
  items: const [],
  totalPrice: 0.0,
  status: 'new',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'incomplete',
  missingFields: const ['customer_name', 'items', 'total_price'],
);

Future<Widget> _buildTestApp(Order order) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      orderPhotosProvider(order.orderRef)
          .overrideWith(() => _FakeOrderPhotosNotifier(const [])),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: OrderCard(order: order, onTap: () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('OrderCard does not show completeness indicators for complete order',
      (tester) async {
    final widget = await _buildTestApp(_completeOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text(OrdersLabels.completenessIncompleteBadge), findsNothing);
    expect(find.textContaining(OrdersLabels.completenessMissingPrefix), findsNothing);
  });

  testWidgets('OrderCard shows completeness indicators for incomplete order',
      (tester) async {
    final widget = await _buildTestApp(_incompleteOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Khách'), findsOneWidget);
    expect(find.text(OrdersLabels.completenessIncompleteBadge), findsOneWidget);
    expect(
      find.textContaining(OrdersLabels.completenessMissingPrefix),
      findsOneWidget,
    );
  });

  testWidgets('OrderCard missing fields indicator shows field labels',
      (tester) async {
    final widget = await _buildTestApp(_incompleteOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.textContaining('tên KH'), findsOneWidget);
    expect(find.textContaining('sản phẩm'), findsOneWidget);
    expect(find.textContaining('tổng tiền'), findsOneWidget);
  });
}
