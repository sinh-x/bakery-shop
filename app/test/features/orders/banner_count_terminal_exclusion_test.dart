import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/filtered_orders_screen.dart' show filterUrgencyActive, filterIncompleteActive;
import 'package:bakery_app/providers/order/incomplete_count_provider.dart';
import 'package:bakery_app/providers/order/order_counts_provider.dart';
import 'package:bakery_app/providers/order/urgency_count_provider.dart';
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

/// Fake [OrderService] that returns canned badge counts from
/// [fetchOrderCounts] (DG-409 Phase 2). The count providers no longer derive
/// from the order list, so [listOrders]/[listActiveOrders] are unused by the
/// count-provider tests below — they remain for any future list-side test.
class _FakeOrderService extends OrderService {
  _FakeOrderService() : super(Dio());

  int urgencyCount = 0;
  int incompleteCount = 0;
  Object? fetchError;

  @override
  Future<({int urgency, int incomplete})> fetchOrderCounts() async {
    if (fetchError != null) throw fetchError!;
    return (urgency: urgencyCount, incomplete: incompleteCount);
  }
}

void main() {
  group('urgencyCountProvider (count API)', () {
    test('returns urgency count from /api/orders/counts', () async {
      final fakeService = _FakeOrderService()..urgencyCount = 3;
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderCountsProvider.future);
      expect(container.read(urgencyCountProvider), 3);
    });

    test('returns 0 when urgency count is zero', () async {
      final fakeService = _FakeOrderService()..urgencyCount = 0;
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderCountsProvider.future);
      expect(container.read(urgencyCountProvider), 0);
    });

    test('returns 0 on fetch error (degraded UX, FR2)', () async {
      final fakeService = _FakeOrderService()
        ..fetchError = StateError('network down');
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      // Read the future so the error settles before reading the sync provider.
      try {
        await container.read(orderCountsProvider.future);
      } catch (_) {}
      expect(container.read(urgencyCountProvider), 0);
    });

    test('returns 0 while loading (before first value)', () {
      final fakeService = _FakeOrderService()..urgencyCount = 5;
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      // Do NOT await — provider is still in loading state.
      expect(container.read(urgencyCountProvider), 0);
    });
  });

  group('incompleteCountProvider (count API)', () {
    test('returns incomplete count from /api/orders/counts', () async {
      final fakeService = _FakeOrderService()..incompleteCount = 2;
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderCountsProvider.future);
      expect(container.read(incompleteCountProvider), 2);
    });

    test('returns 0 when incomplete count is zero', () async {
      final fakeService = _FakeOrderService()..incompleteCount = 0;
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      await container.read(orderCountsProvider.future);
      expect(container.read(incompleteCountProvider), 0);
    });

    test('returns 0 on fetch error (degraded UX, FR2)', () async {
      final fakeService = _FakeOrderService()
        ..fetchError = StateError('network down');
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      try {
        await container.read(orderCountsProvider.future);
      } catch (_) {}
      expect(container.read(incompleteCountProvider), 0);
    });
  });

  group('FR-6: urgency listing includes both critical AND urgent', () {
    test('includes both critical and urgent active orders', () {
      final orders = [
        _order(ref: 'A', status: 'new', urgency: 'critical'),
        _order(ref: 'B', status: 'confirmed', urgency: 'urgent'),
        _order(ref: 'C', status: 'new', urgency: 'normal'),
      ];
      final filtered = filterUrgencyActive(orders);
      expect(filtered, hasLength(2));
      expect(filtered.map((o) => o.orderRef), containsAll(['A', 'B']));
    });

    test('excludes terminal critical/urgent orders from listing', () {
      final orders = [
        _order(ref: 'A', status: 'completed', urgency: 'critical'),
        _order(ref: 'B', status: 'cancelled', urgency: 'urgent'),
        _order(ref: 'C', status: 'new', urgency: 'critical'),
      ];
      final filtered = filterUrgencyActive(orders);
      expect(filtered, hasLength(1));
      expect(filtered.first.orderRef, 'C');
    });
  });

  group('FR-7: incomplete listing filter', () {
    test('excludes terminal incomplete orders from listing', () {
      final orders = [
        _order(ref: 'A', status: 'new', completeness: 'incomplete'),
        _order(ref: 'B', status: 'completed', completeness: 'incomplete'),
        _order(ref: 'C', status: 'cancelled', completeness: 'incomplete'),
      ];
      final filtered = filterIncompleteActive(orders);
      expect(filtered, hasLength(1));
      expect(filtered.first.orderRef, 'A');
    });
  });
}