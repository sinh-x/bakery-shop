import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/cake_queue_item.dart';
import 'package:bakery_app/features/orders/widgets/date_filter_chips.dart';
import 'package:bakery_app/shared/utils/cake_queue_helpers.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';

CakeQueueItem _item({
  required String id,
  required String status,
  String? dueDate,
  String? dueTime,
}) {
  return CakeQueueItem(
    id: id,
    orderId: 'order-$id',
    orderRef: 'REF-$id',
    customerName: 'Test',
    productId: 'p-$id',
    productName: 'Cake $id',
    quantity: 1,
    unitPrice: 0,
    notes: '',
    position: 0,
    status: status,
    isBirthday: false,
    dueDate: dueDate,
    dueTime: dueTime,
    createdAt: null,
  );
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final yesterday = today.subtract(const Duration(days: 1));
  final todayStr = formatApiDate(today);
  final tomorrowStr = formatApiDate(tomorrow);
  final yesterdayStr = formatApiDate(yesterday);
  final pastStr = formatApiDate(DateTime(2020, 1, 1));
  final futureStr = formatApiDate(today.add(const Duration(days: 30)));

  List<CakeQueueItem> sample() => [
        _item(id: '1', status: 'pending', dueDate: todayStr, dueTime: '09:00'),
        _item(id: '2', status: 'pending', dueDate: tomorrowStr, dueTime: '10:00'),
        _item(id: '3', status: 'working', dueDate: yesterdayStr, dueTime: '08:00'),
        _item(id: '4', status: 'ready', dueDate: pastStr, dueTime: '07:00'),
        _item(id: '5', status: 'delivered', dueDate: futureStr, dueTime: '12:00'),
        _item(id: '6', status: 'pending', dueDate: null, dueTime: null),
        _item(id: '7', status: 'pending', dueDate: '', dueTime: ''),
      ];

  group('filterCakeQueueByDate — today', () {
    test('includes today-dated, past-dated, and null/empty-dated items', () {
      final result = filterCakeQueueByDate(sample(), DateFilterOption.today);
      final ids = result.map((i) => i.id).toSet();
      // today (1), yesterday (3), past (4), null (6), empty (7)
      expect(ids, {'1', '3', '4', '6', '7'});
      expect(ids.contains('2'), isFalse); // tomorrow
      expect(ids.contains('5'), isFalse); // future
    });

    test('on a list with only tomorrow items returns empty', () {
      final items = [_item(id: '2', status: 'pending', dueDate: tomorrowStr)];
      expect(filterCakeQueueByDate(items, DateFilterOption.today), isEmpty);
    });

    test('null dueDate item is included under today', () {
      final items = [_item(id: '6', status: 'pending', dueDate: null)];
      expect(filterCakeQueueByDate(items, DateFilterOption.today).length, 1);
    });

    test('empty dueDate item is included under today', () {
      final items = [_item(id: '7', status: 'pending', dueDate: '')];
      expect(filterCakeQueueByDate(items, DateFilterOption.today).length, 1);
    });

    test('far-future dueDate is excluded from today', () {
      final items = [_item(id: '5', status: 'delivered', dueDate: futureStr)];
      expect(filterCakeQueueByDate(items, DateFilterOption.today), isEmpty);
    });
  });

  group('filterCakeQueueByDate — tomorrow', () {
    test('returns only items with dueDate exactly tomorrow', () {
      final result = filterCakeQueueByDate(sample(), DateFilterOption.tomorrow);
      expect(result.length, 1);
      expect(result.single.id, '2');
    });

    test('excludes today, past, future, null and empty', () {
      final result = filterCakeQueueByDate(sample(), DateFilterOption.tomorrow);
      final ids = result.map((i) => i.id).toSet();
      expect(ids.contains('1'), isFalse);
      expect(ids.contains('3'), isFalse);
      expect(ids.contains('4'), isFalse);
      expect(ids.contains('5'), isFalse);
      expect(ids.contains('6'), isFalse);
      expect(ids.contains('7'), isFalse);
    });

    test('on a list with no tomorrow-dated items returns empty', () {
      final items = [_item(id: '1', status: 'pending', dueDate: todayStr)];
      expect(filterCakeQueueByDate(items, DateFilterOption.tomorrow), isEmpty);
    });
  });

  group('filterCakeQueueByDate — today + tomorrow', () {
    test('returns today, tomorrow, past, null, empty — but not far future', () {
      final result =
          filterCakeQueueByDate(sample(), DateFilterOption.todayTomorrow);
      final ids = result.map((i) => i.id).toSet();
      expect(ids, {'1', '2', '3', '4', '6', '7'});
      expect(ids.contains('5'), isFalse);
    });

    test('null dueDate item is included (via today branch)', () {
      final items = [_item(id: '6', status: 'pending', dueDate: null)];
      expect(
          filterCakeQueueByDate(items, DateFilterOption.todayTomorrow).length,
          1);
    });

    test('returns only today when no tomorrow-dated item exists', () {
      final items = [
        _item(id: '1', status: 'pending', dueDate: todayStr),
        _item(id: '3', status: 'working', dueDate: yesterdayStr),
      ];
      final result =
          filterCakeQueueByDate(items, DateFilterOption.todayTomorrow);
      expect(result.length, 2);
      expect(result.map((i) => i.id).toSet(), {'1', '3'});
    });
  });

  group('filterCakeQueueByDate — all', () {
    test('returns every item unchanged', () {
      final items = sample();
      final result = filterCakeQueueByDate(items, DateFilterOption.all);
      expect(result.length, items.length);
      expect(result.map((i) => i.id).toList(), items.map((i) => i.id).toList());
    });

    test('on empty list returns empty', () {
      expect(
          filterCakeQueueByDate(<CakeQueueItem>[], DateFilterOption.all),
          isEmpty);
    });

    test('preserves null and empty dueDate items', () {
      final items = [
        _item(id: '6', status: 'pending', dueDate: null),
        _item(id: '7', status: 'pending', dueDate: ''),
      ];
      expect(filterCakeQueueByDate(items, DateFilterOption.all).length, 2);
    });
  });

  group('filterCakeQueueByDate — boundary cases', () {
    test('yesterday is excluded from tomorrow and today+tomorrow-only subset',
        () {
      final items = [_item(id: '3', status: 'working', dueDate: yesterdayStr)];
      // yesterday IS included under today (overdue), so verify tomorrow excludes it
      expect(filterCakeQueueByDate(items, DateFilterOption.tomorrow), isEmpty);
      // today+tomorrow includes yesterday via today branch
      expect(
          filterCakeQueueByDate(items, DateFilterOption.todayTomorrow).length,
          1);
    });

    test('date format matches formatApiDate output', () {
      expect(todayStr, _formatDate(today));
      expect(tomorrowStr, _formatDate(tomorrow));
    });
  });

  group('groupCakeQueueByStatus — status ordering', () {
    test('returns groups in pending → working → ready → delivered order', () {
      final result = groupCakeQueueByStatus(sample());
      expect(result.keys.toList(), ['pending', 'working', 'ready', 'delivered']);
    });

    test('each group contains only items of that status', () {
      final result = groupCakeQueueByStatus(sample());
      for (final entry in result.entries) {
        for (final item in entry.value) {
          expect(item.status, entry.key);
        }
      }
    });

    test('unknown statuses are dropped', () {
      final items = [
        _item(id: 'x', status: 'cancelled'),
        _item(id: 'y', status: 'weird'),
        _item(id: '1', status: 'pending'),
      ];
      final result = groupCakeQueueByStatus(items);
      expect(result.keys.toSet(), {'pending', 'working', 'ready', 'delivered'});
      expect(result['pending']!.length, 1);
      expect(result['working'], isEmpty);
      expect(result['ready'], isEmpty);
      expect(result['delivered'], isEmpty);
    });
  });

  group('groupCakeQueueByStatus — sort within groups', () {
    test('items without dueDate appear first', () {
      final items = [
        _item(id: 'a', status: 'pending', dueDate: todayStr, dueTime: '09:00'),
        _item(id: 'b', status: 'pending', dueDate: null),
        _item(id: 'c', status: 'pending', dueDate: '', dueTime: ''),
        _item(id: 'd', status: 'pending', dueDate: tomorrowStr, dueTime: '08:00'),
      ];
      final result = groupCakeQueueByStatus(items);
      final ids = result['pending']!.map((i) => i.id).toList();
      // No-date items first (b, c), then by date ascending (a=today, d=tomorrow)
      expect(ids, ['b', 'c', 'a', 'd']);
    });

    test('by dueDate ascending when both have dates', () {
      final items = [
        _item(id: 'late', status: 'pending', dueDate: tomorrowStr),
        _item(id: 'early', status: 'pending', dueDate: todayStr),
        _item(id: 'mid', status: 'pending', dueDate: yesterdayStr),
      ];
      final result = groupCakeQueueByStatus(items);
      final ids = result['pending']!.map((i) => i.id).toList();
      expect(ids, ['mid', 'early', 'late']);
    });

    test('by dueTime ascending when dueDate is equal', () {
      final items = [
        _item(id: 'pm', status: 'working', dueDate: todayStr, dueTime: '14:00'),
        _item(id: 'am', status: 'working', dueDate: todayStr, dueTime: '09:00'),
        _item(id: 'noon', status: 'working', dueDate: todayStr, dueTime: '12:00'),
      ];
      final result = groupCakeQueueByStatus(items);
      final ids = result['working']!.map((i) => i.id).toList();
      expect(ids, ['am', 'noon', 'pm']);
    });

    test('null dueTime sorts before non-empty dueTime at same date', () {
      final items = [
        _item(id: 'withtime', status: 'pending', dueDate: todayStr, dueTime: '09:00'),
        _item(id: 'notime', status: 'pending', dueDate: todayStr, dueTime: null),
      ];
      final result = groupCakeQueueByStatus(items);
      final ids = result['pending']!.map((i) => i.id).toList();
      expect(ids, ['notime', 'withtime']);
    });

    test('no-date items with null/empty dueTime compare equal (stable)', () {
      final items = [
        _item(id: 'nullt', status: 'pending', dueDate: null, dueTime: null),
        _item(id: 'emptyt', status: 'pending', dueDate: '', dueTime: ''),
      ];
      final result = groupCakeQueueByStatus(items);
      expect(result['pending']!.length, 2);
    });

    test('full sort chain: no-date first, then date asc, then time asc', () {
      final items = [
        _item(id: 'p1', status: 'pending', dueDate: todayStr, dueTime: '14:00'),
        _item(id: 'p2', status: 'pending', dueDate: null),
        _item(id: 'p3', status: 'pending', dueDate: todayStr, dueTime: '09:00'),
        _item(id: 'p4', status: 'pending', dueDate: tomorrowStr, dueTime: '08:00'),
        _item(id: 'p5', status: 'pending', dueDate: '', dueTime: ''),
        _item(id: 'p6', status: 'pending', dueDate: todayStr, dueTime: '12:00'),
      ];
      final result = groupCakeQueueByStatus(items);
      final ids = result['pending']!.map((i) => i.id).toList();
      // No-date first: p2, p5
      // today (09:00, 12:00, 14:00): p3, p6, p1
      // tomorrow (08:00): p4
      expect(ids, ['p2', 'p5', 'p3', 'p6', 'p1', 'p4']);
    });
  });

  group('groupCakeQueueByStatus — edge cases', () {
    test('empty input returns all four empty groups', () {
      final result = groupCakeQueueByStatus(<CakeQueueItem>[]);
      expect(result.keys.toList(), ['pending', 'working', 'ready', 'delivered']);
      expect(result['pending'], isEmpty);
      expect(result['working'], isEmpty);
      expect(result['ready'], isEmpty);
      expect(result['delivered'], isEmpty);
    });

    test('all items same status are grouped together', () {
      final items = [
        _item(id: 'r3', status: 'ready', dueDate: todayStr, dueTime: '12:00'),
        _item(id: 'r1', status: 'ready', dueDate: todayStr, dueTime: '08:00'),
        _item(id: 'r2', status: 'ready', dueDate: todayStr, dueTime: '10:00'),
      ];
      final result = groupCakeQueueByStatus(items);
      expect(result['ready']!.length, 3);
      expect(result['ready']!.map((i) => i.id).toList(), ['r1', 'r2', 'r3']);
      expect(result['pending'], isEmpty);
      expect(result['working'], isEmpty);
      expect(result['delivered'], isEmpty);
    });
  });
}
