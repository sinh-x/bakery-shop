import 'package:bakery_app/data/api/order_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _InventoryAuditInterceptor extends Interceptor {
  RequestOptions? request;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    request = options;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'items': <dynamic>[],
          'total': 0,
          'hasMore': false,
          'limit': options.queryParameters['limit'],
          'offset': options.queryParameters['offset'],
        },
      ),
    );
  }
}

void main() {
  test(
    'getInventoryAudit sends bounded offset pagination and parses envelope',
    () async {
      final interceptor = _InventoryAuditInterceptor();
      final service = OrderService(
        Dio(BaseOptions(baseUrl: 'http://test'))..interceptors.add(interceptor),
      );

      final page = await service.getInventoryAudit(
        'ORD 17',
        limit: 500,
        offset: 25,
      );

      expect(interceptor.request!.path, '/api/orders/ORD 17/inventory-audit');
      expect(interceptor.request!.queryParameters, <String, dynamic>{
        'limit': 500,
        'offset': 25,
      });
      expect(page.items, isEmpty);
      expect(page.limit, 500);
      expect(page.offset, 25);
    },
  );

  test(
    'getInventoryAudit defaults to 100 and rejects out-of-range values',
    () async {
      final interceptor = _InventoryAuditInterceptor();
      final service = OrderService(
        Dio(BaseOptions(baseUrl: 'http://test'))..interceptors.add(interceptor),
      );

      await service.getInventoryAudit('ORD-1');
      expect(interceptor.request!.queryParameters['limit'], 100);
      await expectLater(
        service.getInventoryAudit('ORD-1', limit: 501),
        throwsRangeError,
      );
      await expectLater(
        service.getInventoryAudit('ORD-1', offset: -1),
        throwsRangeError,
      );
    },
  );
}
