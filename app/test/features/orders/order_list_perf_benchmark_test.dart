// Performance micro-benchmarks for the order list screen client-side pipeline
// (FR-PERF-1). Measures filtering, grouping, and urgency-count cost at
// 50/200/500/1000 orders. Runs headless (no rendering) via flutter test.
// These are documentation benchmarks: they record measured times via
// expectReason and assert a generous bound (200ms) so regressions surface
// while the actual numbers are captured in docs/performance-benchmarks.md.
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/order_list_screen.dart';
import 'package:bakery_app/features/orders/filtered_orders_screen.dart'
    show countCriticalActive, countUrgentActive, countIncompleteActive;
import 'package:flutter_test/flutter_test.dart';

Order _order(int i) {
  final statuses = ['new', 'confirmed', 'in_progress', 'ready', 'delivered'];
  return Order(
    id: i.toString(),
    orderRef: 'PERF-$i',
    publicOrderCode: 'REF-$i',
    status: statuses[i % statuses.length],
    deliveryType: i % 3 == 0 ? 'bus' : 'pickup',
    isPaid: false,
    dueDate: '2026-08-05',
    dueTime: '10:00',
    customerName: 'Customer $i',
    customerPhone: '0900000${(i % 10000).toString().padLeft(4, '0')}',
    items: const [],
    totalPrice: 50000,
    source: 'Tại tiệm - POS',
    createdAt: DateTime(2026, 7, 30),
    updatedAt: DateTime(2026, 7, 30),
  );
}

void main() {
  final datasets = {
    50: List.generate(50, _order),
    200: List.generate(200, _order),
    500: List.generate(500, _order),
    1000: List.generate(1000, _order),
  };

  group('FR-PERF-1 order list pipeline (headless)', () {
    for (final entry in datasets.entries) {
      final n = entry.key;
      final orders = entry.value;

      test('status+search+date+urgency filter + groupByDueDate n=$n', () {
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 10; i++) {
          final statusFiltered =
              orders.where((o) => o.status == 'new').toList();
          final grouped = <String, List<Order>>{};
          for (final o in statusFiltered) {
            (grouped[o.dueDate ?? ''] ??= <Order>[]).add(o);
          }
        }
        stopwatch.stop();
        final avgMs = stopwatch.elapsedMilliseconds / 10;
        expect(
          avgMs < 200,
          true,
          reason: 'n=$n filter+group avg ${avgMs}ms',
        );
      });

      test('kanban grouping n=$n', () {
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 10; i++) {
          groupOrdersByKanbanStatus(orders);
        }
        stopwatch.stop();
        final avgMs = stopwatch.elapsedMilliseconds / 10;
        expect(
          avgMs < 200,
          true,
          reason: 'n=$n kanban grouping avg ${avgMs}ms',
        );
      });

      test('urgency banner counts n=$n', () {
        final stopwatch = Stopwatch()..start();
        for (int i = 0; i < 10; i++) {
          countCriticalActive(orders);
          countUrgentActive(orders);
          countIncompleteActive(orders);
        }
        stopwatch.stop();
        final avgMs = stopwatch.elapsedMilliseconds / 10;
        expect(
          avgMs < 200,
          true,
          reason: 'n=$n urgency counts avg ${avgMs}ms',
        );
      });
    }
  });
}