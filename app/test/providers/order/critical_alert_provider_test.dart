import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/providers/order/critical_alert_provider.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Order _makeOrder({
  required String orderRef,
  String urgency = 'normal',
  String status = 'new',
  String customerName = 'Khach test',
  String id = '1',
}) {
  return Order(
    id: id,
    orderRef: orderRef,
    customerName: customerName,
    status: status,
    urgency: urgency,
    items: const [],
    totalPrice: 100000.0,
    createdAt: DateTime(2026, 7, 12),
    updatedAt: DateTime(2026, 7, 12),
  );
}

class _FakeOrderService extends OrderService {
  _FakeOrderService() : super(Dio());

  List<Order> orders = [];

  @override
  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async {
    return orders;
  }

  @override
  Future<List<Order>> listActiveOrders({int limit = 200}) async {
    return orders;
  }
}

void main() {
  group('alertedOrderRefsProvider', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(alertedOrderRefsProvider), isEmpty);
    });

    test('addRef adds a ref', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(alertedOrderRefsProvider.notifier).addRef('ORD-001');

      expect(container.read(alertedOrderRefsProvider), contains('ORD-001'));
    });

    test('pruneStaleRefs removes refs not in the active set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(alertedOrderRefsProvider.notifier);
      notifier.addRef('ORD-001');
      notifier.addRef('ORD-002');
      notifier.addRef('ORD-003');

      notifier.pruneStaleRefs({'ORD-001', 'ORD-003'});

      expect(container.read(alertedOrderRefsProvider), contains('ORD-001'));
      expect(container.read(alertedOrderRefsProvider), contains('ORD-003'));
      expect(container.read(alertedOrderRefsProvider), isNot(contains('ORD-002')));
    });

    test('pruneStaleRefs with empty set clears all refs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(alertedOrderRefsProvider.notifier);
      notifier.addRef('ORD-001');
      notifier.pruneStaleRefs({});

      expect(container.read(alertedOrderRefsProvider), isEmpty);
    });
  });

  group('alertActiveProvider', () {
    test('starts as false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(alertActiveProvider), false);
    });

    test('setActive(true) makes it true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(alertActiveProvider.notifier).setActive(true);

      expect(container.read(alertActiveProvider), true);
    });

    test('setActive(false) makes it false after being true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(alertActiveProvider.notifier).setActive(true);
      container.read(alertActiveProvider.notifier).setActive(false);

      expect(container.read(alertActiveProvider), false);
    });
  });

  group('checkNewCriticalOrders (via provider behavior)', () {
    test('detects new critical orders and deduplicates', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _makeOrder(orderRef: 'ORD-001', urgency: 'critical', id: '1'),
      ];
      final container = ProviderContainer(
        overrides: [
          orderServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      // Load orders
      await container.read(orderListProvider.future);
      final orders = container.read(orderListProvider).asData!.value;
      expect(orders, hasLength(1));

      // Verify no alerted refs yet
      expect(container.read(alertedOrderRefsProvider), isEmpty);

      // Manually simulate checkNewCriticalOrders logic
      final alertedNotifier = container.read(alertedOrderRefsProvider.notifier);
      final activeRefs = orders.map((o) => o.orderRef).toSet();
      alertedNotifier.pruneStaleRefs(activeRefs);

      final alertedRefs = container.read(alertedOrderRefsProvider);
      final criticalOrders = orders
          .where((o) => o.urgency == 'critical' && !alertedRefs.contains(o.orderRef))
          .toList();
      expect(criticalOrders, hasLength(1));

      for (final o in criticalOrders) {
        alertedNotifier.addRef(o.orderRef);
      }

      // Now ORD-001 is alerted — second pass should find nothing new
      final activeRefs2 = orders.map((o) => o.orderRef).toSet();
      alertedNotifier.pruneStaleRefs(activeRefs2);
      final alertedRefs2 = container.read(alertedOrderRefsProvider);
      final criticalOrders2 = orders
          .where((o) => o.urgency == 'critical' && !alertedRefs2.contains(o.orderRef))
          .toList();
      expect(criticalOrders2, isEmpty);
    });

    test('prunes stale refs and detects new ones after refresh', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _makeOrder(orderRef: 'ORD-001', urgency: 'critical', id: '1'),
        _makeOrder(orderRef: 'ORD-002', urgency: 'critical', id: '2'),
      ];
      final container = ProviderContainer(
        overrides: [
          orderServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final notifier = container.read(alertedOrderRefsProvider.notifier);

      // Alert both
      var orders = container.read(orderListProvider).asData!.value;
      var activeRefs = orders.map((o) => o.orderRef).toSet();
      notifier.pruneStaleRefs(activeRefs);
      for (final o in orders.where((o) => o.urgency == 'critical')) {
        notifier.addRef(o.orderRef);
      }
      expect(container.read(alertedOrderRefsProvider), hasLength(2));

      // Refresh: ORD-002 removed, ORD-003 added
      fakeService.orders = [
        _makeOrder(orderRef: 'ORD-001', urgency: 'critical', id: '1'),
        _makeOrder(orderRef: 'ORD-003', urgency: 'critical', id: '3'),
      ];
      await container.read(orderListProvider.notifier).refresh();
      await container.read(orderListProvider.future);

      orders = container.read(orderListProvider).asData!.value;
      activeRefs = orders.map((o) => o.orderRef).toSet();
      notifier.pruneStaleRefs(activeRefs);

      // ORD-002 should be gone, ORD-001 remains
      expect(container.read(alertedOrderRefsProvider), contains('ORD-001'));
      expect(container.read(alertedOrderRefsProvider), isNot(contains('ORD-002')));
      expect(container.read(alertedOrderRefsProvider), isNot(contains('ORD-003')));

      // ORD-003 is new — should be detected
      final alertedRefs = container.read(alertedOrderRefsProvider);
      final newCritical = orders
          .where((o) => o.urgency == 'critical' && !alertedRefs.contains(o.orderRef))
          .toList();
      expect(newCritical, hasLength(1));
      expect(newCritical.first.orderRef, 'ORD-003');
    });

    test('does not count urgent or normal orders', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _makeOrder(orderRef: 'ORD-001', urgency: 'urgent', id: '1'),
        _makeOrder(orderRef: 'ORD-002', urgency: 'normal', id: '2'),
      ];
      final container = ProviderContainer(
        overrides: [
          orderServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final orders = container.read(orderListProvider).asData!.value;
      final notifier = container.read(alertedOrderRefsProvider.notifier);
      final activeRefs = orders.map((o) => o.orderRef).toSet();
      notifier.pruneStaleRefs(activeRefs);

      final alertedRefs = container.read(alertedOrderRefsProvider);
      final critical = orders
          .where((o) => o.urgency == 'critical' && !alertedRefs.contains(o.orderRef))
          .toList();
      expect(critical, isEmpty);
    });
  });
}
