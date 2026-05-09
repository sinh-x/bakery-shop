import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/order_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Order _order({
  required int id,
  required String ref,
  required String status,
  String deliveryType = 'pickup',
  bool isPaid = false,
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: status,
    deliveryType: deliveryType,
    isPaid: isPaid,
    customerName: 'Test',
    items: const [],
    totalPrice: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('groupOrdersByKanbanStatus', () {
    test('grouping empty list produces empty columns', () {
      final grouped = groupOrdersByKanbanStatus([]);

      expect(grouped.length, 6);
      for (final entries in grouped.values) {
        expect(entries, isEmpty);
      }
    });

    test('maps single new order to new column', () {
      final orders = [_order(id: 1, ref: 'ORD-001', status: 'new')];
      final grouped = groupOrdersByKanbanStatus(orders);

      expect(grouped['new']!.length, 1);
      expect(grouped['new']!.first.orderRef, 'ORD-001');
      expect(grouped['confirmed']!, isEmpty);
      expect(grouped['in_progress']!, isEmpty);
      expect(grouped['ready']!, isEmpty);
      expect(grouped['to_deliver']!, isEmpty);
      expect(grouped['awaiting_payment']!, isEmpty);
    });

    test('maps each active status to correct column', () {
      final orders = [
        _order(id: 1, ref: 'ORD-NEW', status: 'new'),
        _order(id: 2, ref: 'ORD-CONF', status: 'confirmed'),
        _order(id: 3, ref: 'ORD-IP', status: 'in_progress'),
        _order(id: 4, ref: 'ORD-RDY', status: 'ready'),
      ];
      final grouped = groupOrdersByKanbanStatus(orders);

      expect(grouped['new']!.length, 1);
      expect(grouped['new']!.first.orderRef, 'ORD-NEW');
      expect(grouped['confirmed']!.length, 1);
      expect(grouped['confirmed']!.first.orderRef, 'ORD-CONF');
      expect(grouped['in_progress']!.length, 1);
      expect(grouped['in_progress']!.first.orderRef, 'ORD-IP');
      expect(grouped['ready']!.length, 1);
      expect(grouped['ready']!.first.orderRef, 'ORD-RDY');
    });

    group('virtual column: to_deliver', () {
      test('ready+bus goes to to_deliver, not ready', () {
        final orders = [
          _order(id: 1, ref: 'ORD-BUS', status: 'ready', deliveryType: 'bus'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['to_deliver']!.length, 1);
        expect(grouped['to_deliver']!.first.orderRef, 'ORD-BUS');
        expect(grouped['ready']!, isEmpty);
      });

      test('ready+door goes to to_deliver, not ready', () {
        final orders = [
          _order(id: 1, ref: 'ORD-DOOR', status: 'ready', deliveryType: 'door'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['to_deliver']!.length, 1);
        expect(grouped['to_deliver']!.first.orderRef, 'ORD-DOOR');
        expect(grouped['ready']!, isEmpty);
      });

      test('ready+pickup stays in ready, not to_deliver', () {
        final orders = [
          _order(id: 1, ref: 'ORD-PU', status: 'ready', deliveryType: 'pickup'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['ready']!.length, 1);
        expect(grouped['ready']!.first.orderRef, 'ORD-PU');
        expect(grouped['to_deliver']!, isEmpty);
      });
    });

    group('virtual column: awaiting_payment', () {
      test('delivered+unpaid goes to awaiting_payment', () {
        final orders = [
          _order(id: 1, ref: 'ORD-DEL-UNPAID', status: 'delivered', isPaid: false),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['awaiting_payment']!.length, 1);
        expect(grouped['awaiting_payment']!.first.orderRef, 'ORD-DEL-UNPAID');
      });

      test('delivered+paid does NOT go to awaiting_payment or any column', () {
        final orders = [
          _order(id: 1, ref: 'ORD-DEL-PAID', status: 'delivered', isPaid: true),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['awaiting_payment']!, isEmpty);
        // Paid delivered order should not appear in any active column
        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        expect(totalVisible, 0);
      });
    });

    group('terminal statuses excluded', () {
      test('completed orders do not appear in any active column', () {
        final orders = [
          _order(id: 1, ref: 'ORD-COMPLETE', status: 'completed'),
          _order(id: 2, ref: 'ORD-NEW', status: 'new'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 1);
        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        expect(totalVisible, 1);
      });

      test('cancelled orders do not appear in any active column', () {
        final orders = [
          _order(id: 1, ref: 'ORD-CANCEL', status: 'cancelled'),
          _order(id: 2, ref: 'ORD-NEW', status: 'new'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 1);
        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        expect(totalVisible, 1);
      });

      test('only completed and cancelled are excluded, all other active orders visible', () {
        final orders = [
          _order(id: 1, ref: 'ORD-NEW', status: 'new'),
          _order(id: 2, ref: 'ORD-CONF', status: 'confirmed'),
          _order(id: 3, ref: 'ORD-IP', status: 'in_progress'),
          _order(id: 4, ref: 'ORD-RDY', status: 'ready'),
          _order(id: 5, ref: 'ORD-BUS', status: 'ready', deliveryType: 'bus'),
          _order(id: 6, ref: 'ORD-COMP', status: 'completed'),
          _order(id: 7, ref: 'ORD-CANCEL', status: 'cancelled'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        // 5 active + 0 terminal = 5 visible
        // new(1) + confirmed(1) + in_progress(1) + ready(1) + to_deliver(1) = 5
        expect(totalVisible, 5);
        // Verify completed/cancelled are absent
        final allOrderRefs = grouped.values.expand((l) => l).map((o) => o.orderRef).toSet();
        expect(allOrderRefs.contains('ORD-COMP'), isFalse);
        expect(allOrderRefs.contains('ORD-CANCEL'), isFalse);
      });
    });

    group('count equality', () {
      test('each column count equals its card count in a mixed dataset', () {
        final orders = [
          _order(id: 1, ref: 'ORD-1', status: 'new'),
          _order(id: 2, ref: 'ORD-2', status: 'new'),
          _order(id: 3, ref: 'ORD-3', status: 'confirmed'),
          _order(id: 4, ref: 'ORD-4', status: 'confirmed'),
          _order(id: 5, ref: 'ORD-5', status: 'confirmed'),
          _order(id: 6, ref: 'ORD-6', status: 'in_progress'),
          _order(id: 7, ref: 'ORD-7', status: 'ready'),
          _order(id: 8, ref: 'ORD-8', status: 'ready'),
          _order(id: 9, ref: 'ORD-9', status: 'ready', deliveryType: 'bus'),
          _order(id: 10, ref: 'ORD-10', status: 'delivered', isPaid: false),
          _order(id: 11, ref: 'ORD-11', status: 'delivered', isPaid: false),
          _order(id: 12, ref: 'ORD-12', status: 'delivered', isPaid: false),
          _order(id: 13, ref: 'ORD-13', status: 'completed'),
          _order(id: 14, ref: 'ORD-14', status: 'cancelled'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 2);
        expect(grouped['confirmed']!.length, 3);
        expect(grouped['in_progress']!.length, 1);
        expect(grouped['ready']!.length, 2);
        expect(grouped['to_deliver']!.length, 1);
        expect(grouped['awaiting_payment']!.length, 3);

        // Verify all active orders are accounted for (no duplicates, no missing)
        var totalCards = 0;
        for (final c in grouped.values) {
          totalCards += c.length;
        }
        // 2+3+1+2+1+3 = 12 active
        expect(totalCards, 12);
        // 14 total - 2 terminal = 12 active
        expect(totalCards, orders.length - 2);
      });

      test('older active order beyond newest-50 cutoff appears in correct column', () {
        final orders = <Order>[];
        // Older order
        orders.add(_order(id: 900, ref: 'ORD-OLD', status: 'new'));
        // 60 newer fillers (mixed statuses)
        for (var i = 1; i <= 60; i++) {
          orders.add(_order(
            id: i,
            ref: 'ORD-${i.toString().padLeft(3, '0')}',
            status: 'confirmed',
          ));
        }
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 1);
        expect(grouped['new']!.first.orderRef, 'ORD-OLD');
        expect(grouped['new']!.first.id, '900');
        expect(grouped['confirmed']!.length, 60);
      });
    });

    group('all active statuses covered', () {
      test('delivered+unpaid is the only way into awaiting_payment', () {
        final orders = [
          _order(id: 1, ref: 'ORD-A', status: 'new', isPaid: false),
          _order(id: 2, ref: 'ORD-B', status: 'confirmed', isPaid: false),
          _order(id: 3, ref: 'ORD-C', status: 'in_progress', isPaid: false),
          _order(id: 4, ref: 'ORD-D', status: 'ready', isPaid: false),
          _order(id: 5, ref: 'ORD-E', status: 'delivered', isPaid: false),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        // Only delivered+unpaid goes to awaiting_payment
        expect(grouped['awaiting_payment']!.length, 1);
        expect(grouped['awaiting_payment']!.first.orderRef, 'ORD-E');
        // Other unpaid orders stay in their status columns
        expect(grouped['new']!.length, 1);
        expect(grouped['confirmed']!.length, 1);
        expect(grouped['in_progress']!.length, 1);
        expect(grouped['ready']!.length, 1);
      });
    });

    group('multi-order customer visibility', () {
      test('customer with 3 active new orders shows all 3 in new column', () {
        final orders = [
          _order(id: 90, ref: 'ORD-260508-009', status: 'new'),
          _order(id: 91, ref: 'ORD-260508-010', status: 'new'),
          _order(id: 95, ref: 'ORD-260508-014', status: 'new'),
          _order(id: 1, ref: 'ORD-001', status: 'new'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 4);
        final newRefs = grouped['new']!.map((o) => o.orderRef).toSet();
        expect(newRefs, containsAll(['ORD-260508-009', 'ORD-260508-010', 'ORD-260508-014']));
      });

      test('customer with 3 active orders across statuses: all in correct columns', () {
        final orders = [
          _order(id: 90, ref: 'ORD-90', status: 'new'),
          _order(id: 91, ref: 'ORD-91', status: 'confirmed'),
          _order(id: 95, ref: 'ORD-95', status: 'new'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 2);
        expect(grouped['confirmed']!.length, 1);
        expect(grouped['confirmed']!.first.orderRef, 'ORD-91');
      });

      test('customer 3 orders with one cancelled: cancelled excluded, active remain', () {
        final orders = [
          _order(id: 90, ref: 'ORD-90', status: 'new'),
          _order(id: 91, ref: 'ORD-91', status: 'new'),
          _order(id: 89, ref: 'ORD-89', status: 'cancelled'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 2);
        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        expect(totalVisible, 2);
      });

      test('multi-customer multi-order mixed dataset: all active orders visible', () {
        final orders = [
          _order(id: 90, ref: 'A1', status: 'new'),
          _order(id: 91, ref: 'A2', status: 'new'),
          _order(id: 92, ref: 'A3', status: 'new'),
          _order(id: 80, ref: 'B1', status: 'confirmed'),
          _order(id: 81, ref: 'B2', status: 'confirmed'),
          _order(id: 70, ref: 'C1', status: 'in_progress'),
          _order(id: 60, ref: 'D1', status: 'ready'),
          _order(id: 61, ref: 'D2', status: 'ready'),
          _order(id: 99, ref: 'CANCEL', status: 'cancelled'),
        ];
        final grouped = groupOrdersByKanbanStatus(orders);

        expect(grouped['new']!.length, 3);
        expect(grouped['confirmed']!.length, 2);
        expect(grouped['in_progress']!.length, 1);
        expect(grouped['ready']!.length, 2);

        var totalVisible = 0;
        for (final c in grouped.values) {
          totalVisible += c.length;
        }
        expect(totalVisible, 8);
        expect(grouped['new']!.map((o) => o.orderRef), containsAll(['A1', 'A2', 'A3']));
        expect(grouped['confirmed']!.map((o) => o.orderRef), containsAll(['B1', 'B2']));
      });
    });
  });
}


