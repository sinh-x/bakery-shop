import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockInterceptor extends Interceptor {
  final List<Map<String, dynamic>> responseData;
  String? lastPath;
  Map<String, dynamic>? lastQueryParams;

  _MockInterceptor(this.responseData);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastQueryParams = options.queryParameters;
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: responseData),
    );
  }
}

class _CreateOrderInterceptor extends Interceptor {
  Object? lastBody;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastBody = options.data;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: _makeOrderJson(
          id: 1,
          ref: 'ORD-260518-001',
          dueDate: '2026-05-18',
        ),
      ),
    );
  }
}

Map<String, dynamic> _makeOrderJson({
  required int id,
  required String ref,
  String status = 'new',
  String customerName = 'Khach test',
  String customerPhone = '0900000001',
  String? dueDate,
  bool isPaid = false,
  String deliveryType = 'pickup',
}) {
  return {
    'id': id.toString(),
    'orderRef': ref,
    'status': status,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'dueDate': dueDate,
    'dueTime': null,
    'deliveryType': deliveryType,
    'deliveryAddress': '',
    'items': [],
    'totalPrice': 200000.0,
    'amountPaid': isPaid ? 200000.0 : 0.0,
    'isPaid': isPaid,
    'notes': '',
    'source': '',
    'packingChecklist': [],
    'shippingFee': 0.0,
    'workTicketPrintedAt': null,
    'createdBy': '',
    'createdAt': '2026-05-01T10:00:00',
    'updatedAt': '2026-05-01T10:00:00',
  };
}

List<Map<String, dynamic>> _olderActiveWithFiller() {
  final rows = <Map<String, dynamic>>[];
  rows.add(
    _makeOrderJson(
      id: 900,
      ref: 'ORD-260101-900',
      customerName: 'Anh Ba',
      customerPhone: '0901000900',
    ),
  );
  for (var i = 1; i <= 60; i++) {
    rows.add(
      _makeOrderJson(
        id: i,
        ref: 'ORD-260501-${i.toString().padLeft(3, '0')}',
        customerName: 'Khach $i',
        customerPhone: '090000${i.toString().padLeft(4, '0')}',
      ),
    );
  }
  return rows;
}

void main() {
  group('OrderService active_only support', () {
    test('listOrders sends active_only=true when activeOnly is true', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.listOrders(activeOnly: true);

      expect(interceptor.lastQueryParams, containsPair('active_only', true));
    });

    test(
      'listOrders does NOT send active_only when activeOnly is false',
      () async {
        final interceptor = _MockInterceptor([]);
        final dio = Dio()..interceptors.add(interceptor);
        final service = OrderService(dio);

        await service.listOrders();

        expect(interceptor.lastQueryParams?['active_only'], isNull);
      },
    );

    test('listActiveOrders sends active_only=true', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.listActiveOrders();

      expect(interceptor.lastQueryParams, containsPair('active_only', true));
    });

    test('listOrders sends due_date_from and due_date_to', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.listOrders(
        dueDateFrom: '2026-05-17',
        dueDateTo: '2026-05-18',
      );

      expect(
        interceptor.lastQueryParams,
        containsPair('due_date_from', '2026-05-17'),
      );
      expect(
        interceptor.lastQueryParams,
        containsPair('due_date_to', '2026-05-18'),
      );
    });
  });

  group('OrderService createOrder payload', () {
    test('createOrder sends dueDate when provided', () async {
      final interceptor = _CreateOrderInterceptor();
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.createOrder(
        customerName: 'Khach le',
        dueDate: '2026-05-18',
        items: const <Map<String, dynamic>>[],
      );

      final body = interceptor.lastBody as Map<String, dynamic>;
      expect(body, containsPair('dueDate', '2026-05-18'));
    });
  });

  group('OrderService returns complete active dataset', () {
    test('older active order is included beyond 50-filler rows', () async {
      final dataset = _olderActiveWithFiller();
      final interceptor = _MockInterceptor(dataset);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      final orders = await service.listOrders(activeOnly: true);

      expect(orders.length, 61);
      expect(orders.any((o) => o.orderRef == 'ORD-260101-900'), isTrue);
    });

    test('search by ref finds older active order beyond 50-cutoff', () async {
      final dataset = _olderActiveWithFiller();
      final interceptor = _MockInterceptor(dataset);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      final orders = await service.listOrders(activeOnly: true);

      const q = 'ORD-260101-900';
      final matches = orders
          .where(
            (o) =>
                o.orderRef.toLowerCase().contains(q.toLowerCase()) ||
                o.customerName.toLowerCase().contains(q.toLowerCase()) ||
                o.customerPhone.contains(q),
          )
          .toList();
      expect(matches.length, 1);
      expect(matches.first.orderRef, 'ORD-260101-900');
    });

    test(
      'search by customer name finds older active order beyond 50-cutoff',
      () async {
        final dataset = _olderActiveWithFiller();
        final interceptor = _MockInterceptor(dataset);
        final dio = Dio()..interceptors.add(interceptor);
        final service = OrderService(dio);

        final orders = await service.listOrders(activeOnly: true);

        final matches = orders
            .where((o) => o.customerName.toLowerCase().contains('anh ba'))
            .toList();
        expect(matches.length, 1);
        expect(matches.first.orderRef, 'ORD-260101-900');
      },
    );

    test('search by phone finds older active order beyond 50-cutoff', () async {
      final dataset = _olderActiveWithFiller();
      final interceptor = _MockInterceptor(dataset);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      final orders = await service.listOrders(activeOnly: true);

      final matches = orders
          .where((o) => o.customerPhone.contains('0901000900'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.orderRef, 'ORD-260101-900');
    });
  });

  group('OrderListNotifier uses activeOnly', () {
    test('_fetch builds with activeOnly=true via listOrders', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [orderServiceProvider.overrideWithValue(OrderService(dio))],
      );

      final notifier = container.read(orderListProvider.notifier);
      await notifier.build();

      expect(interceptor.lastQueryParams, containsPair('active_only', true));
    });
  });

  group('OrderHistoryNotifier uses history range', () {
    test(
      'setDateRange queries without active_only and with due_date range',
      () async {
        final interceptor = _MockInterceptor([]);
        final dio = Dio()..interceptors.add(interceptor);
        final container = ProviderContainer(
          overrides: [
            orderServiceProvider.overrideWithValue(OrderService(dio)),
          ],
        );

        final notifier = container.read(orderHistoryProvider.notifier);
        await notifier.build();
        await notifier.setDateRange(
          DateTime(2026, 5, 17),
          DateTime(2026, 5, 18),
        );

        expect(interceptor.lastQueryParams?['active_only'], isNull);
        expect(interceptor.lastQueryParams?['due_date_from'], '2026-05-17');
        expect(interceptor.lastQueryParams?['due_date_to'], '2026-05-18');
      },
    );

    test('validateRange blocks selections longer than 7 days', () {
      final container = ProviderContainer();
      final notifier = container.read(orderHistoryProvider.notifier);
      final message = notifier.validateRange(
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 8),
      );
      expect(message, isNotNull);
    });
  });

  group('multi-order customer visibility', () {
    List<Map<String, dynamic>> customerWith3ActiveOrders() {
      final rows = <Map<String, dynamic>>[
        _makeOrderJson(id: 90, ref: 'ORD-260508-009', customerName: 'Thôn Nữ'),
        _makeOrderJson(id: 91, ref: 'ORD-260508-010', customerName: 'Thôn Nữ'),
        _makeOrderJson(id: 95, ref: 'ORD-260508-014', customerName: 'Thôn Nữ'),
      ];
      for (var i = 1; i <= 10; i++) {
        rows.add(
          _makeOrderJson(
            id: i,
            ref: 'ORD-260501-${i.toString().padLeft(3, '0')}',
          ),
        );
      }
      return rows;
    }

    List<Map<String, dynamic>> customerWith3ActiveAndFillerOrders() {
      final rows = <Map<String, dynamic>>[
        _makeOrderJson(id: 900, ref: 'ORD-260101-900', customerName: 'Quen A'),
        _makeOrderJson(id: 901, ref: 'ORD-260101-901', customerName: 'Quen A'),
        _makeOrderJson(id: 902, ref: 'ORD-260101-902', customerName: 'Quen A'),
      ];
      for (var i = 1; i <= 60; i++) {
        rows.add(
          _makeOrderJson(
            id: i,
            ref: 'ORD-260501-${i.toString().padLeft(3, '0')}',
            customerName: 'Khach $i',
          ),
        );
      }
      return rows;
    }

    test('search by customer name finds all 3 matching orders', () async {
      final dataset = customerWith3ActiveOrders();
      final interceptor = _MockInterceptor(dataset);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      final orders = await service.listOrders(activeOnly: true);
      final matches = orders
          .where((o) => o.customerName.toLowerCase().contains('thôn nữ'))
          .toList();

      expect(matches.length, 3);
      final refs = matches.map((o) => o.orderRef).toSet();
      expect(
        refs,
        containsAll(['ORD-260508-009', 'ORD-260508-010', 'ORD-260508-014']),
      );
    });

    test(
      'search by exact ref finds the single matching order among 3 for same customer',
      () async {
        final dataset = customerWith3ActiveOrders();
        final interceptor = _MockInterceptor(dataset);
        final dio = Dio()..interceptors.add(interceptor);
        final service = OrderService(dio);

        final orders = await service.listOrders(activeOnly: true);
        const query = 'ORD-260508-010';
        final matches = orders
            .where(
              (o) => o.orderRef.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();

        expect(matches.length, 1);
        expect(matches.first.orderRef, 'ORD-260508-010');
        expect(matches.first.customerName, 'Thôn Nữ');
      },
    );

    test(
      'customer name search finds all 3 even when 60 filler orders exist',
      () async {
        final dataset = customerWith3ActiveAndFillerOrders();
        final interceptor = _MockInterceptor(dataset);
        final dio = Dio()..interceptors.add(interceptor);
        final service = OrderService(dio);

        final orders = await service.listOrders(activeOnly: true);
        expect(orders.length, 63);

        final matches = orders
            .where((o) => o.customerName.toLowerCase().contains('quen a'))
            .toList();
        expect(matches.length, 3);
        final refs = matches.map((o) => o.orderRef).toSet();
        expect(
          refs,
          containsAll(['ORD-260101-900', 'ORD-260101-901', 'ORD-260101-902']),
        );
      },
    );
  });
}
