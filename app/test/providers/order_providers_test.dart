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
      Response(
        requestOptions: options,
        statusCode: 200,
        data: responseData,
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

    test('listOrders does NOT send active_only when activeOnly is false', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.listOrders();

      expect(interceptor.lastQueryParams?['active_only'], isNull);
    });

    test('listActiveOrders sends active_only=true', () async {
      final interceptor = _MockInterceptor([]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OrderService(dio);

      await service.listActiveOrders();

      expect(interceptor.lastQueryParams, containsPair('active_only', true));
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

    test('search by customer name finds older active order beyond 50-cutoff', () async {
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
    });

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
      final container = ProviderContainer(overrides: [
        orderServiceProvider.overrideWithValue(OrderService(dio)),
      ]);

      final notifier = container.read(orderListProvider.notifier);
      await notifier.build();

      expect(interceptor.lastQueryParams, containsPair('active_only', true));
    });
  });
}
