import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/providers/order/incomplete_count_provider.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/providers/order/urgency_count_provider.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Order _order({
  required String ref,
  required String status,
  String urgency = 'normal',
  String completeness = 'complete',
}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: 'Test',
    status: status,
    urgency: urgency,
    completeness: completeness,
    items: const [],
    totalPrice: 0,
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
  group('urgencyCountProvider', () {
    test('counts critical and urgent active orders', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'confirmed', urgency: 'urgent'),
        _order(ref: 'C', status: 'new', urgency: 'normal'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(urgencyCountProvider), 2);
    });

    test('excludes completed orders from count - FR-5/AC5', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'completed', urgency: 'critical'),
        _order(ref: 'C', status: 'completed', urgency: 'urgent'),
        _order(ref: 'D', status: 'new', urgency: 'urgent'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      // Only A and D are active + critical/urgent.
      expect(container.read(urgencyCountProvider), 2);
    });

    test('excludes cancelled orders from count - FR-5/AC5', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'cancelled', urgency: 'critical'),
        _order(ref: 'C', status: 'cancelled', urgency: 'urgent'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(urgencyCountProvider), 1);
    });

    test('counts all active statuses (delivered is still active)', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'delivered', urgency: 'critical'),
        _order(ref: 'B', status: 'ready', urgency: 'urgent'),
        _order(ref: 'C', status: 'in_progress', urgency: 'critical'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(urgencyCountProvider), 3);
    });

    test('zero when all urgent orders are terminal', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'completed', urgency: 'critical'),
        _order(ref: 'B', status: 'cancelled', urgency: 'urgent'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(urgencyCountProvider), 0);
    });
  });

  group('incompleteCountProvider', () {
    test('counts incomplete active orders', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', completeness: 'incomplete'),
        _order(ref: 'B', status: 'confirmed', completeness: 'incomplete'),
        _order(ref: 'C', status: 'new', completeness: 'complete'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(incompleteCountProvider), 2);
    });

    test('excludes completed incomplete orders - FR-7/AC6', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', completeness: 'incomplete'),
        _order(ref: 'B', status: 'completed', completeness: 'incomplete'),
        _order(ref: 'C', status: 'completed', completeness: 'incomplete'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(incompleteCountProvider), 1);
    });

    test('excludes cancelled incomplete orders - FR-7/AC6', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', completeness: 'incomplete'),
        _order(ref: 'B', status: 'cancelled', completeness: 'incomplete'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      expect(container.read(incompleteCountProvider), 1);
    });
  });

  group('FR-6: urgency listing includes both critical AND urgent', () {
    // Reuse the same filter logic as filtered_orders_screen.dart applyFilter
    List<Order> applyUrgencyFilter(List<Order> orders) {
      const activeStatuses = [
        'new',
        'confirmed',
        'in_progress',
        'ready',
        'delivered',
      ];
      final active = orders.where((o) => activeStatuses.contains(o.status));
      return active
          .where(
            (o) => o.urgency == urgencyCritical || o.urgency == urgencyUrgent,
          )
          .toList();
    }

    test('includes both critical and urgent active orders', () {
      final orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'confirmed', urgency: 'urgent'),
        _order(ref: 'C', status: 'new', urgency: 'normal'),
      ];
      final filtered = applyUrgencyFilter(orders);
      expect(filtered, hasLength(2));
      expect(filtered.map((o) => o.orderRef), containsAll(['A', 'B']));
    });

    test('excludes terminal critical/urgent orders from listing', () {
      final orders = [
        _order(ref: 'A', status: 'completed', urgency: 'critical'),
        _order(ref: 'B', status: 'cancelled', urgency: 'urgent'),
        _order(ref: 'C', status: 'new', urgency: 'critical'),
      ];
      final filtered = applyUrgencyFilter(orders);
      expect(filtered, hasLength(1));
      expect(filtered.first.orderRef, 'C');
    });

    test('listing count matches urgencyCountProvider count', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'confirmed', urgency: 'urgent'),
        _order(ref: 'C', status: 'completed', urgency: 'critical'),
        _order(ref: 'D', status: 'cancelled', urgency: 'urgent'),
        _order(ref: 'E', status: 'ready', urgency: 'normal'),
        _order(ref: 'F', status: 'delivered', urgency: 'critical'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final orders = container.read(orderListProvider).asData!.value;
      final providerCount = container.read(urgencyCountProvider);
      final listingCount = applyUrgencyFilter(orders).length;

      expect(providerCount, listingCount);
      expect(providerCount, 3);
    });
  });

  group('FR-7: incomplete listing matches incompleteCountProvider', () {
    List<Order> applyIncompleteFilter(List<Order> orders) {
      const activeStatuses = [
        'new',
        'confirmed',
        'in_progress',
        'ready',
        'delivered',
      ];
      final active = orders.where((o) => activeStatuses.contains(o.status));
      return active
          .where((o) => o.completeness == completenessIncomplete)
          .toList();
    }

    test('listing count matches incompleteCountProvider count', () async {
      final fakeService = _FakeOrderService();
      fakeService.orders = [
        _order(ref: 'A', status: 'new', completeness: 'incomplete'),
        _order(ref: 'B', status: 'completed', completeness: 'incomplete'),
        _order(ref: 'C', status: 'confirmed', completeness: 'incomplete'),
        _order(ref: 'D', status: 'cancelled', completeness: 'incomplete'),
        _order(ref: 'E', status: 'new', completeness: 'complete'),
      ];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderListProvider.future);
      final orders = container.read(orderListProvider).asData!.value;
      final providerCount = container.read(incompleteCountProvider);
      final listingCount = applyIncompleteFilter(orders).length;

      expect(providerCount, listingCount);
      expect(providerCount, 2);
    });
  });
}