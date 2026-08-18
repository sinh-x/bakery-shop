import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/dashboard/widgets/today_order_list.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

Order _order({
  required String ref,
  String status = 'new',
  String? dueDate,
  String? dueTime,
  String customerName = 'Test',
  double totalPrice = 0,
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: customerName,
    status: status,
    dueDate: dueDate,
    dueTime: dueTime,
    totalPrice: totalPrice,
    items: const [],
    createdAt: DateTime(2026, 8, 5),
    updatedAt: DateTime(2026, 8, 5),
  );
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => 'http://test.local';
}

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  _FakeOrderPhotosNotifier() : super('unused');

  @override
  Future<List<OrderPhoto>> build() async => const [];
}

Future<void> _pump(WidgetTester tester, List<Order> orders) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final refs = orders.map((o) => o.orderRef).toSet();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiBaseUrlProvider.overrideWith(_FakeApiBaseUrlNotifier.new),
        for (final ref in refs)
          orderPhotosProvider(ref)
              .overrideWith(_FakeOrderPhotosNotifier.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodayOrderList(orders: orders),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  group('groupTodayOrdersByStatus', () {
    test('empty list → empty map', () {
      expect(groupTodayOrdersByStatus(const []), isEmpty);
    });

    test('groups orders by status in workflow order', () {
      final orders = [
        _order(ref: 'A', status: 'completed'),
        _order(ref: 'B', status: 'new'),
        _order(ref: 'C', status: 'new'),
        _order(ref: 'D', status: 'cancelled'),
        _order(ref: 'E', status: 'delivered'),
      ];
      final grouped = groupTodayOrdersByStatus(orders);
      // Workflow order: new, confirmed, in_progress, ready, delivered,
      // completed, cancelled — only statuses with orders appear.
      expect(grouped.keys.toList(), [
        'new',
        'delivered',
        'completed',
        'cancelled',
      ]);
      expect(grouped['new']!.map((o) => o.orderRef), ['B', 'C']);
      expect(grouped['delivered']!.map((o) => o.orderRef), ['E']);
      expect(grouped['completed']!.map((o) => o.orderRef), ['A']);
      expect(grouped['cancelled']!.map((o) => o.orderRef), ['D']);
    });

    test('completed orders appear in their own group (FR6/AC6)', () {
      final orders = [
        _order(ref: 'POS1', status: 'completed'),
        _order(ref: 'POS2', status: 'completed'),
        _order(ref: 'A', status: 'new'),
      ];
      final grouped = groupTodayOrdersByStatus(orders);
      expect(grouped['completed']!.length, 2);
      expect(grouped['new']!.length, 1);
    });

    test('sorts within a group by dueDate asc then dueTime asc', () {
      final orders = [
        _order(ref: 'late', status: 'new', dueDate: '2026-08-06'),
        _order(ref: 'nodate', status: 'new'),
        _order(ref: 'early', status: 'new', dueDate: '2026-08-05'),
        _order(ref: 'earlyAM', status: 'new', dueDate: '2026-08-05', dueTime: '07:00'),
        _order(ref: 'earlyPM', status: 'new', dueDate: '2026-08-05', dueTime: '15:00'),
      ];
      final grouped = groupTodayOrdersByStatus(orders);
      // No-due-date first, then by dueDate asc; within a date, empty dueTime
      // sorts before non-empty (empty string < '07:00'), mirroring
      // groupDeliveryOrdersByStatus.
      expect(grouped['new']!.map((o) => o.orderRef), [
        'nodate',
        'early',
        'earlyAM',
        'earlyPM',
        'late',
      ]);
    });
  });

  group('TodayOrderList widget', () {
    testWidgets('empty order list shows empty-state message', (tester) async {
      await _pump(tester, const []);
      expect(find.text(SharedLabels.khongCoDonHomNay), findsOneWidget);
    });

    testWidgets('orders grouped by status with a count per group (AC6)',
        (tester) async {
      final orders = [
        _order(ref: 'A', status: 'new', customerName: 'An'),
        _order(ref: 'B', status: 'new', customerName: 'Bình'),
        _order(ref: 'C', status: 'delivered', customerName: 'Cúc'),
        _order(ref: 'D', status: 'completed', customerName: 'Dung'),
        _order(ref: 'E', status: 'cancelled', customerName: 'Em'),
      ];
      await _pump(tester, orders);

      // Each non-empty status group renders a header with its VN label +
      // count badge. Headers: "Mới" (2), "Đã giao" (1), "Hoàn thành" (1),
      // "Đã hủy" (1).
      expect(find.text(OrdersLabels.statusNew), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text(OrdersLabels.statusDelivered), findsOneWidget);
      expect(find.text(OrdersLabels.statusCompleted), findsOneWidget);
      expect(find.text(OrdersLabels.statusCancelled), findsOneWidget);

      // Each order's customer name appears via its OrderCard.
      for (final name in ['An', 'Bình', 'Cúc', 'Dung', 'Em']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('completed orders appear in their own group (AC6)', (tester) async {
      final orders = [
        _order(ref: 'POS1', status: 'completed', customerName: 'POS one'),
        _order(ref: 'POS2', status: 'completed', customerName: 'POS two'),
        _order(ref: 'A', status: 'new', customerName: 'Active'),
      ];
      await _pump(tester, orders);

      // Completed group header + count badge "2".
      expect(find.text(OrdersLabels.statusCompleted), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // New group header + count badge "1".
      expect(find.text(OrdersLabels.statusNew), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // Completed order rows render.
      expect(find.text('POS one'), findsOneWidget);
      expect(find.text('POS two'), findsOneWidget);
    });

    testWidgets('groups render in workflow order', (tester) async {
      // Insert in reverse workflow order to verify rendering follows the
      // canonical workflow order (new → ... → cancelled).
      final orders = [
        _order(ref: 'Z', status: 'cancelled'),
        _order(ref: 'Y', status: 'completed'),
        _order(ref: 'X', status: 'delivered'),
        _order(ref: 'W', status: 'new'),
      ];
      await _pump(tester, orders);

      // Collect the y-offsets of each status header text to assert order.
      final labels = [
        OrdersLabels.statusNew,
        OrdersLabels.statusDelivered,
        OrdersLabels.statusCompleted,
        OrdersLabels.statusCancelled,
      ];
      final offsets = <String, double>{};
      for (final label in labels) {
        final element = find.text(label).evaluate().single;
        final renderBox = element.renderObject as RenderBox;
        final origin = renderBox.localToGlobal(Offset.zero);
        offsets[label] = origin.dy;
      }
      expect(offsets[labels[0]]! < offsets[labels[1]]!, true);
      expect(offsets[labels[1]]! < offsets[labels[2]]!, true);
      expect(offsets[labels[2]]! < offsets[labels[3]]!, true);
    });

    testWidgets('all groups expanded by default (Phase 10 FR6/AC6)',
        (tester) async {
      final orders = [
        _order(ref: 'A', status: 'new', customerName: 'An'),
        _order(ref: 'B', status: 'completed', customerName: 'Bình'),
      ];
      await _pump(tester, orders);

      // Both status headers present.
      expect(find.text(OrdersLabels.statusNew), findsOneWidget);
      expect(find.text(OrdersLabels.statusCompleted), findsOneWidget);
      // Order cards visible — groups default to expanded.
      expect(find.text('An'), findsOneWidget);
      expect(find.text('Bình'), findsOneWidget);
      // Expand (down) chevron shown when expanded.
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));
      expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);
    });

    testWidgets('tapping a header collapses its group (Phase 10 FR6/AC6)',
        (tester) async {
      final orders = [
        _order(ref: 'A', status: 'new', customerName: 'An'),
        _order(ref: 'B', status: 'new', customerName: 'Bình'),
        _order(ref: 'C', status: 'completed', customerName: 'Cúc'),
      ];
      await _pump(tester, orders);

      // Sanity: "new" group has 2 orders visible initially.
      expect(find.text('An'), findsOneWidget);
      expect(find.text('Bình'), findsOneWidget);

      // Tap the "new" status header to collapse it.
      await tester.tap(find.text(OrdersLabels.statusNew));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // "new" group now collapsed: chevron flipped, order rows hidden.
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      expect(find.text('An'), findsNothing);
      expect(find.text('Bình'), findsNothing);
      // Header label + count badge still visible when collapsed.
      expect(find.text(OrdersLabels.statusNew), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // "completed" group unaffected — still expanded.
      expect(find.text(OrdersLabels.statusCompleted), findsOneWidget);
      expect(find.text('Cúc'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      // Tap again to re-expand.
      await tester.tap(find.text(OrdersLabels.statusNew));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Order rows visible again.
      expect(find.text('An'), findsOneWidget);
      expect(find.text('Bình'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));
      expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);
    });
  });
}