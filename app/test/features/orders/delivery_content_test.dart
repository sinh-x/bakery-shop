import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/widgets/delivery_content.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';

Order _order({
  required int id,
  required String ref,
  required String status,
  String deliveryType = 'pickup',
  String? dueDate,
  String? dueTime,
  double totalPrice = 100000,
  String customerName = 'Test',
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: status,
    deliveryType: deliveryType,
    isPaid: false,
    customerName: customerName,
    items: const [],
    totalPrice: totalPrice,
    dueDate: dueDate,
    dueTime: dueTime,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );
}

class _FakeOrderListNotifier extends OrderListNotifier {
  final List<Order> orders;
  _FakeOrderListNotifier(this.orders);

  @override
  Future<List<Order>> build() async => orders;

  @override
  Future<void> refresh() async {}
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  final String url;
  _FakeApiBaseUrlNotifier(this.url);

  @override
  String build() => url;
}

Widget buildTestWidget(List<Order> orders) {
  return ProviderScope(
    overrides: [
      orderListProvider.overrideWith(
        () => _FakeOrderListNotifier(orders),
      ),
      apiBaseUrlProvider.overrideWith(
        () => _FakeApiBaseUrlNotifier('http://test.local'),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: DeliveryContent(),
      ),
    ),
  );
}

void main() {
  group('DeliveryContent', () {
    testWidgets('defaults Hôm nay filter selected', (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      final todayChip = find.text(OrdersLabels.deliveryFilterToday);
      expect(todayChip, findsOneWidget);

      final chipWidget = tester.widget<FilterChip>(
        find.ancestor(of: todayChip, matching: find.byType(FilterChip)),
      );
      expect(chipWidget.selected, isTrue);
    });

    testWidgets('shows Hôm nay empty state when only future orders exist',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-FUTURE',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2099-06-15',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });

    testWidgets('shows Tất cả empty state when no delivery orders',
        (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      await tester.tap(find.text(OrdersLabels.deliveryFilterAll));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyAll), findsOneWidget);
    });

    testWidgets('toggling to Tất cả shows future-dated orders',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-FUTURE',
          status: 'new',
          deliveryType: 'door',
          dueDate: '2099-06-15',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);

      await tester.tap(find.text(OrdersLabels.deliveryFilterAll));
      await tester.pumpAndSettle();

      expect(find.text('ORD-FUTURE'), findsOneWidget);
    });

    testWidgets('renders today delivery order cards', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-TODAY',
          status: 'ready',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
          customerName: 'Nguyen Van A',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text('ORD-TODAY'), findsOneWidget);
      expect(find.text('Nguyen Van A'), findsOneWidget);
    });

    testWidgets('groups orders by status with both visible', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-NEW',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
        ),
        _order(
          id: 2,
          ref: 'ORD-READY',
          status: 'ready',
          deliveryType: 'door',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text('ORD-NEW'), findsOneWidget);
      expect(find.text('ORD-READY'), findsOneWidget);
    });

    testWidgets('shows overdue orders in Hôm nay view', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-OVERDUE',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-01',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text('ORD-OVERDUE'), findsOneWidget);
    });

    testWidgets('shows unscheduled orders in Hôm nay view', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-NO-DATE',
          status: 'confirmed',
          deliveryType: 'door',
          dueDate: null,
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text('ORD-NO-DATE'), findsOneWidget);
    });

    testWidgets('non-delivery orders excluded from Hôm nay', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-PICKUP',
          status: 'new',
          deliveryType: 'pickup',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });

    testWidgets('terminal status orders excluded from delivery',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-COMPLETE',
          status: 'completed',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });
  });
}
