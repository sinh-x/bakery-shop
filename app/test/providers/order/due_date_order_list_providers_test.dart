import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/providers/order/due_date_order_list_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Order _order({required String ref, String status = 'new'}) {
  return Order(
    id: ref,
    orderRef: ref,
    customerName: 'Test',
    status: status,
    items: const [],
    totalPrice: 0,
    createdAt: DateTime(2026, 8, 15),
    updatedAt: DateTime(2026, 8, 15),
  );
}

/// Records the arguments of every `listOrders` call so the test can assert
/// the provider fetched via `due_date` / `due_date_from`+`due_date_to` (CQ-1
/// — the order list now comes from a separate fetch, not `summary.orders`).
class _RecordingOrderService extends OrderService {
  _RecordingOrderService() : super(Dio());

  List<Order> orders = const [];
  final List<Map<String, Object?>> calls = [];

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
    calls.add({
      'status': status,
      'dueDate': dueDate,
      'dueDateFrom': dueDateFrom,
      'dueDateTo': dueDateTo,
      'limit': limit,
      'offset': offset,
      'activeOnly': activeOnly,
    });
    return orders;
  }
}

void main() {
  group('dueDateOrdersProvider', () {
    test('fetches orders via GET /api/orders?due_date=<date> (CQ-1)', () async {
      final service = _RecordingOrderService()
        ..orders = [_order(ref: 'A'), _order(ref: 'B')];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        dueDateOrdersProvider('2026-08-15').future,
      );

      // The provider issued exactly one listOrders call scoped to the date.
      expect(service.calls.length, 1);
      expect(service.calls.single['dueDate'], '2026-08-15');
      // Active-only is false so completed/cancelled orders are included
      // (matches the former summary.orders semantics).
      expect(service.calls.single['activeOnly'], false);
      // CQ-13: no silent truncation — limit is -1 (unbounded) so every
      // order due on the day is fetched.
      expect(service.calls.single['limit'], -1);
      // The returned order list is what the UI renders.
      expect(result.map((o) => o.orderRef), ['A', 'B']);
    });

    test('different dates resolve independently (family keying)', () async {
      final service = _RecordingOrderService()..orders = [_order(ref: 'A')];
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(dueDateOrdersProvider('2026-08-15').future);
      await container.read(dueDateOrdersProvider('2026-08-16').future);

      expect(service.calls.length, 2);
      expect(service.calls[0]['dueDate'], '2026-08-15');
      expect(service.calls[1]['dueDate'], '2026-08-16');
    });
  });
}
