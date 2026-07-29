import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/utils/delivery_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Order _order({
  required int id,
  required String ref,
  required String status,
  String deliveryType = 'bus',
  String? dueDate,
  String? dueTime,
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: status,
    deliveryType: deliveryType,
    customerName: 'Test',
    items: const [],
    totalPrice: 0,
    dueDate: dueDate,
    dueTime: dueTime,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  final yesterday = _formatDate(
    DateTime.now().subtract(const Duration(days: 1)),
  );
  final today = _formatDate(DateTime.now());
  final tomorrow = _formatDate(
    DateTime.now().add(const Duration(days: 1)),
  );

  group('filterDeliveryOrders', () {
    group('todayOnly: true', () {
      test('excludes non-delivery types (pickup)', () {
        final orders = [
          _order(id: 1, ref: 'ORD-001', status: 'new', deliveryType: 'pickup'),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered, isEmpty);
      });

      test('excludes terminal statuses (completed, cancelled)', () {
        final orders = [
          _order(id: 1, ref: 'ORD-COMP', status: 'completed'),
          _order(id: 2, ref: 'ORD-CANCEL', status: 'cancelled'),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered, isEmpty);
      });

      test('includes non-terminal statuses with dueDate today', () {
        final orders = [
          _order(id: 1, ref: 'ORD-NEW', status: 'new', dueDate: today),
          _order(id: 2, ref: 'ORD-CONF', status: 'confirmed', dueDate: today),
          _order(id: 3, ref: 'ORD-IP', status: 'in_progress', dueDate: today),
          _order(id: 4, ref: 'ORD-RDY', status: 'ready', dueDate: today),
          _order(id: 5, ref: 'ORD-DEL', status: 'delivered', dueDate: today),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 5);
      });

      test('includes overdue orders (dueDate yesterday)', () {
        final orders = [
          _order(id: 1, ref: 'ORD-OVERDUE', status: 'new', dueDate: yesterday),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
        expect(filtered.first.orderRef, 'ORD-OVERDUE');
      });

      test('excludes future orders (dueDate tomorrow)', () {
        final orders = [
          _order(id: 1, ref: 'ORD-FUTURE', status: 'new', dueDate: tomorrow),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered, isEmpty);
      });

      test('includes orders with null dueDate', () {
        final orders = [
          _order(id: 1, ref: 'ORD-NULL', status: 'new', dueDate: null),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });

      test('includes orders with empty dueDate', () {
        final orders = [
          _order(id: 1, ref: 'ORD-EMPTY', status: 'new', dueDate: ''),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });

      test('includes legacy delivery type', () {
        final orders = [
          _order(
            id: 1,
            ref: 'ORD-LEGACY',
            status: 'new',
            deliveryType: 'delivery',
            dueDate: today,
          ),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });

      test('includes door delivery type', () {
        final orders = [
          _order(
            id: 1,
            ref: 'ORD-DOOR',
            status: 'new',
            deliveryType: 'door',
            dueDate: today,
          ),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });

      test('includes bus delivery type', () {
        final orders = [
          _order(
            id: 1,
            ref: 'ORD-BUS',
            status: 'new',
            deliveryType: 'bus',
            dueDate: today,
          ),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });
    });

    group('todayOnly: false (Tất cả)', () {
      test('includes all non-terminal delivery orders regardless of dueDate', () {
        final orders = [
          _order(id: 1, ref: 'ORD-TODAY', status: 'new', dueDate: today),
          _order(id: 2, ref: 'ORD-TOM', status: 'new', dueDate: tomorrow),
          _order(id: 3, ref: 'ORD-YEST', status: 'new', dueDate: yesterday),
          _order(id: 4, ref: 'ORD-NULL', status: 'new', dueDate: null),
          _order(id: 5, ref: 'ORD-EMPTY', status: 'new', dueDate: ''),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: false);
        expect(filtered.length, 5);
      });

      test('excludes non-delivery types', () {
        final orders = [
          _order(
            id: 1,
            ref: 'ORD-PU',
            status: 'new',
            deliveryType: 'pickup',
          ),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: false);
        expect(filtered, isEmpty);
      });

      test('excludes terminal statuses', () {
        final orders = [
          _order(id: 1, ref: 'ORD-COMP', status: 'completed'),
          _order(id: 2, ref: 'ORD-CANCEL', status: 'cancelled'),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: false);
        expect(filtered, isEmpty);
      });
    });

    group('date boundary', () {
      test('boundary: today at midnight exactly is included', () {
        final orders = [
          _order(id: 1, ref: 'ORD-TODAY', status: 'new', dueDate: today),
        ];
        final filtered = filterDeliveryOrders(orders, todayOnly: true);
        expect(filtered.length, 1);
      });
    });
  });

  group('groupDeliveryOrdersByStatus', () {
    test('empty list produces empty groups', () {
      final grouped = groupDeliveryOrdersByStatus([]);

      expect(grouped.length, 5);
      for (final entries in grouped.values) {
        expect(entries, isEmpty);
      }
    });

    test('groups by status in workflow order', () {
      final orders = [
        _order(id: 1, ref: 'ORD-1', status: 'new'),
        _order(id: 2, ref: 'ORD-2', status: 'confirmed'),
        _order(id: 3, ref: 'ORD-3', status: 'in_progress'),
        _order(id: 4, ref: 'ORD-4', status: 'ready'),
        _order(id: 5, ref: 'ORD-5', status: 'delivered'),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 1);
      expect(grouped['new']!.first.orderRef, 'ORD-1');
      expect(grouped['confirmed']!.length, 1);
      expect(grouped['confirmed']!.first.orderRef, 'ORD-2');
      expect(grouped['in_progress']!.length, 1);
      expect(grouped['in_progress']!.first.orderRef, 'ORD-3');
      expect(grouped['ready']!.length, 1);
      expect(grouped['ready']!.first.orderRef, 'ORD-4');
      expect(grouped['delivered']!.length, 1);
      expect(grouped['delivered']!.first.orderRef, 'ORD-5');
    });

    test('no-due-date orders appear first within each status', () {
      final orders = [
        _order(id: 1, ref: 'ORD-WITH-DATE', status: 'new', dueDate: today),
        _order(id: 2, ref: 'ORD-NO-DATE', status: 'new', dueDate: null),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 2);
      expect(grouped['new']!.first.orderRef, 'ORD-NO-DATE');
      expect(grouped['new']!.last.orderRef, 'ORD-WITH-DATE');
    });

    test('orders sorted by dueDate ascending within status', () {
      final orders = [
        _order(id: 1, ref: 'ORD-LATER', status: 'new', dueDate: tomorrow),
        _order(id: 2, ref: 'ORD-EARLY', status: 'new', dueDate: yesterday),
        _order(id: 3, ref: 'ORD-TODAY', status: 'new', dueDate: today),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 3);
      expect(grouped['new']![0].orderRef, 'ORD-EARLY');
      expect(grouped['new']![1].orderRef, 'ORD-TODAY');
      expect(grouped['new']![2].orderRef, 'ORD-LATER');
    });

    test('same dueDate sorted by dueTime ascending', () {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-LATE',
          status: 'new',
          dueDate: today,
          dueTime: '14:00',
        ),
        _order(
          id: 2,
          ref: 'ORD-EARLY',
          status: 'new',
          dueDate: today,
          dueTime: '09:00',
        ),
        _order(
          id: 3,
          ref: 'ORD-MID',
          status: 'new',
          dueDate: today,
          dueTime: '10:30',
        ),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']![0].orderRef, 'ORD-EARLY');
      expect(grouped['new']![1].orderRef, 'ORD-MID');
      expect(grouped['new']![2].orderRef, 'ORD-LATE');
    });

    test('no-due-date and empty-dueDate treated equivalently', () {
      final orders = [
        _order(id: 1, ref: 'ORD-DATE', status: 'new', dueDate: today),
        _order(id: 2, ref: 'ORD-NULL', status: 'new', dueDate: null),
        _order(id: 3, ref: 'ORD-EMPTY', status: 'new', dueDate: ''),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 3);
      expect(grouped['new']![0].orderRef, 'ORD-NULL');
      expect(grouped['new']![1].orderRef, 'ORD-EMPTY');
      expect(grouped['new']![2].orderRef, 'ORD-DATE');
    });

    test('null dueTime does not crash sorting', () {
      final orders = [
        _order(id: 1, ref: 'ORD-1', status: 'new', dueDate: today, dueTime: null),
        _order(id: 2, ref: 'ORD-2', status: 'new', dueDate: today, dueTime: '10:00'),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 2);
    });

    test('all 5 workflow statuses present in result map', () {
      final grouped = groupDeliveryOrdersByStatus([]);

      expect(grouped.containsKey('new'), isTrue);
      expect(grouped.containsKey('confirmed'), isTrue);
      expect(grouped.containsKey('in_progress'), isTrue);
      expect(grouped.containsKey('ready'), isTrue);
      expect(grouped.containsKey('delivered'), isTrue);
    });

    test('count equality across mixed dataset', () {
      final orders = [
        _order(id: 1, ref: 'ORD-1', status: 'new'),
        _order(id: 2, ref: 'ORD-2', status: 'new'),
        _order(id: 3, ref: 'ORD-3', status: 'confirmed'),
        _order(id: 4, ref: 'ORD-4', status: 'confirmed'),
        _order(id: 5, ref: 'ORD-5', status: 'confirmed'),
        _order(id: 6, ref: 'ORD-6', status: 'in_progress'),
        _order(id: 7, ref: 'ORD-7', status: 'ready'),
        _order(id: 8, ref: 'ORD-8', status: 'ready'),
        _order(id: 9, ref: 'ORD-9', status: 'delivered'),
      ];
      final grouped = groupDeliveryOrdersByStatus(orders);

      expect(grouped['new']!.length, 2);
      expect(grouped['confirmed']!.length, 3);
      expect(grouped['in_progress']!.length, 1);
      expect(grouped['ready']!.length, 2);
      expect(grouped['delivered']!.length, 1);

      var total = 0;
      for (final c in grouped.values) {
        total += c.length;
      }
      expect(total, 9);
    });
  });

  group('deriveTimeSlot', () {
    test('derives slot from dueTime hour (14:30 -> 14:00)', () {
      expect(deriveTimeSlot('14:30'), '14:00');
    });

    test('derives slot from dueTime hour (07:15 -> 7:00)', () {
      expect(deriveTimeSlot('07:15'), '7:00');
    });

    test('derives slot from dueTime hour (6:00 -> 6:00)', () {
      expect(deriveTimeSlot('6:00'), '6:00');
    });

    test('derives slot from dueTime hour (21:45 -> 21:00)', () {
      expect(deriveTimeSlot('21:45'), '21:00');
    });

    test('returns null for null dueTime', () {
      expect(deriveTimeSlot(null), isNull);
    });

    test('returns null for empty dueTime', () {
      expect(deriveTimeSlot(''), isNull);
    });

    test('returns null for malformed dueTime (no colon)', () {
      expect(deriveTimeSlot('1400'), isNull);
    });

    test('returns null for non-numeric hour', () {
      expect(deriveTimeSlot('ab:30'), isNull);
    });
  });

  group('groupDeliveryOrdersByTimeSlot', () {
    test('groups orders by auto-derived dueTime hour', () {
      final orders = [
        _order(id: 1, ref: 'ORD-A', status: 'new', dueTime: '14:30'),
        _order(id: 2, ref: 'ORD-B', status: 'new', dueTime: '14:00'),
        _order(id: 3, ref: 'ORD-C', status: 'new', dueTime: '09:15'),
      ];
      final grouped = groupDeliveryOrdersByTimeSlot(orders);

      expect(grouped['14:00']!.length, 2);
      expect(grouped['9:00']!.length, 1);
    });

    test('orders without dueTime fall into no-slot group', () {
      final orders = [
        _order(id: 1, ref: 'ORD-NO-TIME', status: 'new', dueTime: null),
        _order(id: 2, ref: 'ORD-EMPTY-TIME', status: 'new', dueTime: ''),
      ];
      final grouped = groupDeliveryOrdersByTimeSlot(orders);

      expect(grouped[OrdersLabels.deliveryCalendarNoSlot]!.length, 2);
    });

    test('orders with dueTime outside 6:00-21:00 fall into no-slot group', () {
      final orders = [
        _order(id: 1, ref: 'ORD-EARLY', status: 'new', dueTime: '05:30'),
        _order(id: 2, ref: 'ORD-LATE', status: 'new', dueTime: '22:00'),
      ];
      final grouped = groupDeliveryOrdersByTimeSlot(orders);

      expect(grouped[OrdersLabels.deliveryCalendarNoSlot]!.length, 2);
    });

    test('derives slot ignoring the stored deliveryTimeSlot DB column', () {
      // FR1: the stored `deliveryTimeSlot` column is ignored by the frontend;
      // the slot is auto-derived from `dueTime`.
      final orders = [
        Order(
          id: '1',
          orderRef: 'ORD-STORED',
          status: 'new',
          deliveryType: 'door',
          customerName: 'Test',
          items: const [],
          totalPrice: 0,
          dueDate: today,
          dueTime: '14:30',
          deliveryTimeSlot: '09:00', // stale stored value, must be ignored
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];
      final grouped = groupDeliveryOrdersByTimeSlot(orders);

      expect(grouped['14:00']!.length, 1);
      expect(grouped.containsKey('9:00'), isFalse);
    });

    test('empty list produces empty map', () {
      final grouped = groupDeliveryOrdersByTimeSlot([]);

      expect(grouped, isEmpty);
    });
  });

  group('groupDeliveryOrdersByDayAndSlot', () {
    test('groups orders by dueDate + derived slot (AC1)', () {
      final orders = [
        _order(
            id: 1,
            ref: 'ORD-A',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '14:30'),
        _order(
            id: 2,
            ref: 'ORD-B',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '14:00'),
        _order(
            id: 3,
            ref: 'ORD-C',
            status: 'new',
            dueDate: '2026-07-29',
            dueTime: '09:15'),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);

      expect(grouped[(day: '2026-07-28', slot: '14:00')]!.length, 2);
      expect(grouped[(day: '2026-07-29', slot: '9:00')]!.length, 1);
    });

    test('orders without dueTime fall into unscheduled slot for their day', () {
      final orders = [
        _order(
            id: 1,
            ref: 'ORD-NO-TIME',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: null),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);

      expect(
        grouped[(day: '2026-07-28', slot: OrdersLabels.deliveryCalendarNoSlot)]!
            .length,
        1,
      );
    });

    test('orders with dueTime outside 6:00-21:00 are unscheduled', () {
      final orders = [
        _order(
            id: 1,
            ref: 'ORD-EARLY',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '05:30'),
        _order(
            id: 2,
            ref: 'ORD-LATE',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '22:00'),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);

      expect(
        grouped[(day: '2026-07-28', slot: OrdersLabels.deliveryCalendarNoSlot)]!
            .length,
        2,
      );
    });

    test('orders without dueDate are dropped (calendar is date-aware)', () {
      final orders = [
        _order(id: 1, ref: 'ORD-NO-DATE', status: 'new', dueTime: '14:30'),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);

      expect(grouped, isEmpty);
    });

    test('orders within a cell sort by dueTime then orderRef', () {
      final orders = [
        _order(
            id: 1,
            ref: 'ORD-B',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '14:30'),
        _order(
            id: 2,
            ref: 'ORD-A',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '14:30'),
        _order(
            id: 3,
            ref: 'ORD-C',
            status: 'new',
            dueDate: '2026-07-28',
            dueTime: '14:00'),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);
      final cell = grouped[(day: '2026-07-28', slot: '14:00')]!;

      expect(cell.map((o) => o.orderRef).toList(), ['ORD-C', 'ORD-A', 'ORD-B']);
    });

    test('derives slot ignoring the stored deliveryTimeSlot DB column', () {
      final orders = [
        Order(
          id: '1',
          orderRef: 'ORD-STORED',
          status: 'new',
          deliveryType: 'door',
          customerName: 'Test',
          items: const [],
          totalPrice: 0,
          dueDate: today,
          dueTime: '14:30',
          deliveryTimeSlot: '09:00', // stale stored value, must be ignored
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];
      final grouped = groupDeliveryOrdersByDayAndSlot(orders);

      expect(grouped[(day: today, slot: '14:00')]!.length, 1);
      expect(grouped.containsKey((day: today, slot: '9:00')), isFalse);
    });

    test('empty list produces empty map', () {
      expect(groupDeliveryOrdersByDayAndSlot([]), isEmpty);
    });
  });

  group('startOfWeek', () {
    test('returns Monday for a Wednesday', () {
      final wed = DateTime(2026, 7, 29); // 2026-07-29 is a Wednesday
      final mon = startOfWeek(wed);
      expect(mon, DateTime(2026, 7, 27));
    });

    test('returns same date when given a Monday', () {
      final mon = DateTime(2026, 7, 27);
      expect(startOfWeek(mon), DateTime(2026, 7, 27));
    });

    test('returns Monday for a Sunday', () {
      final sun = DateTime(2026, 8, 2); // 2026-08-02 is a Sunday
      expect(startOfWeek(sun), DateTime(2026, 7, 27));
    });
  });

  group('daysOfWeek', () {
    test('returns 7 days Mon..Sun starting at weekStart', () {
      final days = daysOfWeek(DateTime(2026, 7, 27));
      expect(days.length, 7);
      expect(days.first, DateTime(2026, 7, 27)); // Monday
      expect(days.last, DateTime(2026, 8, 2)); // Sunday
      expect(days.map((d) => d.weekday), [1, 2, 3, 4, 5, 6, 7]);
    });
  });
}
