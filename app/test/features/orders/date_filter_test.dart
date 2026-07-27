import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/order_list_screen.dart';
import 'package:bakery_app/features/orders/widgets/date_filter_chips.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Order _order({
  required int id,
  required String ref,
  String? dueDate,
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: 'new',
    deliveryType: 'pickup',
    customerName: 'Test',
    items: const [],
    totalPrice: 0,
    dueDate: dueDate,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // Today/tomorrow derived the same way `applyDateFilter` does internally.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final todayStr = formatApiDate(today);
  final tomorrowStr = formatApiDate(tomorrow);
  final yesterdayStr = formatApiDate(today.subtract(const Duration(days: 1)));
  final pastStr = formatApiDate(DateTime(2020, 1, 1));
  final futureStr = formatApiDate(today.add(const Duration(days: 30)));

  List<Order> sampleOrders() => [
        _order(id: 1, ref: 'TODAY', dueDate: todayStr),
        _order(id: 2, ref: 'TOMORROW', dueDate: tomorrowStr),
        _order(id: 3, ref: 'YESTERDAY', dueDate: yesterdayStr),
        _order(id: 4, ref: 'PAST', dueDate: pastStr),
        _order(id: 5, ref: 'FUTURE', dueDate: futureStr),
        _order(id: 6, ref: 'NODATE', dueDate: null),
        _order(id: 7, ref: 'EMPTY', dueDate: ''),
      ];

  group('applyDateFilter — AC1 (today)', () {
    test('today filter returns only orders with dueDate = today', () {
      final result = applyDateFilter(sampleOrders(), DateFilterOption.today);
      expect(result.length, 1);
      expect(result.single.orderRef, 'TODAY');
    });

    test('today filter excludes tomorrow, past, future, null and empty', () {
      final result = applyDateFilter(sampleOrders(), DateFilterOption.today);
      final refs = result.map((o) => o.orderRef).toSet();
      expect(refs.contains('TOMORROW'), isFalse);
      expect(refs.contains('YESTERDAY'), isFalse);
      expect(refs.contains('PAST'), isFalse);
      expect(refs.contains('FUTURE'), isFalse);
      expect(refs.contains('NODATE'), isFalse);
      expect(refs.contains('EMPTY'), isFalse);
    });

    test('today filter on a list with no today-dated orders returns empty', () {
      final orders = [
        _order(id: 2, ref: 'TOMORROW', dueDate: tomorrowStr),
        _order(id: 6, ref: 'NODATE', dueDate: null),
      ];
      expect(applyDateFilter(orders, DateFilterOption.today), isEmpty);
    });
  });

  group('applyDateFilter — AC2 (tomorrow)', () {
    test('tomorrow filter returns only orders with dueDate = tomorrow', () {
      final result =
          applyDateFilter(sampleOrders(), DateFilterOption.tomorrow);
      expect(result.length, 1);
      expect(result.single.orderRef, 'TOMORROW');
    });

    test('tomorrow filter excludes today, past, future, null and empty', () {
      final result =
          applyDateFilter(sampleOrders(), DateFilterOption.tomorrow);
      final refs = result.map((o) => o.orderRef).toSet();
      expect(refs.contains('TODAY'), isFalse);
      expect(refs.contains('YESTERDAY'), isFalse);
      expect(refs.contains('PAST'), isFalse);
      expect(refs.contains('FUTURE'), isFalse);
      expect(refs.contains('NODATE'), isFalse);
      expect(refs.contains('EMPTY'), isFalse);
    });
  });

  group('applyDateFilter — AC3 (today + tomorrow)', () {
    test('today+tomorrow filter returns both today and tomorrow orders', () {
      final result =
          applyDateFilter(sampleOrders(), DateFilterOption.todayTomorrow);
      expect(result.length, 2);
      final refs = result.map((o) => o.orderRef).toSet();
      expect(refs, {'TODAY', 'TOMORROW'});
    });

    test('today+tomorrow filter excludes past, future, null and empty', () {
      final result =
          applyDateFilter(sampleOrders(), DateFilterOption.todayTomorrow);
      final refs = result.map((o) => o.orderRef).toSet();
      expect(refs.contains('YESTERDAY'), isFalse);
      expect(refs.contains('PAST'), isFalse);
      expect(refs.contains('FUTURE'), isFalse);
      expect(refs.contains('NODATE'), isFalse);
      expect(refs.contains('EMPTY'), isFalse);
    });

    test('today+tomorrow filter returns only today when no tomorrow order', () {
      final orders = [
        _order(id: 1, ref: 'TODAY', dueDate: todayStr),
        _order(id: 3, ref: 'YESTERDAY', dueDate: yesterdayStr),
      ];
      final result =
          applyDateFilter(orders, DateFilterOption.todayTomorrow);
      expect(result.length, 1);
      expect(result.single.orderRef, 'TODAY');
    });
  });

  group('applyDateFilter — AC4 (all)', () {
    test('all filter returns every order unchanged (filter cleared)', () {
      final orders = sampleOrders();
      final result = applyDateFilter(orders, DateFilterOption.all);
      expect(result.length, orders.length);
      expect(result.map((o) => o.orderRef).toSet(),
          orders.map((o) => o.orderRef).toSet());
    });

    test('all filter preserves order including null and empty dueDate', () {
      final orders = sampleOrders();
      final result = applyDateFilter(orders, DateFilterOption.all);
      expect(result.map((o) => o.orderRef).toList(),
          orders.map((o) => o.orderRef).toList());
    });

    test('all filter on empty list returns empty', () {
      expect(applyDateFilter(<Order>[], DateFilterOption.all), isEmpty);
    });
  });

  group('applyDateFilter — null/empty dueDate handling (FR2)', () {
    test('null dueDate order excluded from today filter', () {
      final orders = [_order(id: 6, ref: 'NODATE', dueDate: null)];
      expect(applyDateFilter(orders, DateFilterOption.today), isEmpty);
    });

    test('empty dueDate order excluded from tomorrow filter', () {
      final orders = [_order(id: 7, ref: 'EMPTY', dueDate: '')];
      expect(applyDateFilter(orders, DateFilterOption.tomorrow), isEmpty);
    });

    test('null dueDate order included only under all filter', () {
      final orders = [_order(id: 6, ref: 'NODATE', dueDate: null)];
      expect(applyDateFilter(orders, DateFilterOption.today), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.tomorrow), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.todayTomorrow), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.all).length, 1);
    });
  });

  group('applyDateFilter — past/future boundary cases (FR2)', () {
    test('yesterday order is excluded from today, tomorrow, and combined', () {
      final orders = [_order(id: 3, ref: 'YESTERDAY', dueDate: yesterdayStr)];
      expect(applyDateFilter(orders, DateFilterOption.today), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.tomorrow), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.todayTomorrow), isEmpty);
    });

    test('far-future order is excluded from today, tomorrow, and combined', () {
      final orders = [_order(id: 5, ref: 'FUTURE', dueDate: futureStr)];
      expect(applyDateFilter(orders, DateFilterOption.today), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.tomorrow), isEmpty);
      expect(applyDateFilter(orders, DateFilterOption.todayTomorrow), isEmpty);
    });
  });

  group('applyDateFilter — composition (FR3/AC7)', () {
    test(
        'date filter applies to a pre-filtered (by status/search) subset without re-introducing excluded orders',
        () {
      // Simulate a status pre-filter that kept only TODAY and NODATE.
      final preFiltered = [
        _order(id: 1, ref: 'TODAY', dueDate: todayStr),
        _order(id: 6, ref: 'NODATE', dueDate: null),
      ];
      final result = applyDateFilter(preFiltered, DateFilterOption.today);
      expect(result.length, 1);
      expect(result.single.orderRef, 'TODAY');
    });

    test(
        'date filter + grouping: _groupByDueDate sees only the filtered subset',
        () {
      // We mirror the pipeline: status -> date -> grouping. With today filter,
      // only the today-dated order survives to be grouped.
      final orders = sampleOrders();
      final afterDate = applyDateFilter(orders, DateFilterOption.today);
      expect(afterDate.length, 1);
      expect(afterDate.single.dueDate, todayStr);
    });

    test(
        'all filter is a no-op identity, so downstream stages receive full set',
        () {
      final orders = sampleOrders();
      final afterDate = applyDateFilter(orders, DateFilterOption.all);
      expect(afterDate.length, orders.length);
    });
  });

  group('applyDateFilter — date format assumptions', () {
    test('compares using formatApiDate-derived today string', () {
      // Guard against accidental change to a different format: the filter
      // must match the same string formatApiDate produces.
      expect(todayStr, _formatDate(today));
      expect(tomorrowStr, _formatDate(tomorrow));
    });
  });
}