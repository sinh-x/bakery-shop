import 'package:bakery_app/data/api/work_item_service.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures PATCH requests and returns a canned WorkItem JSON.
class _CaptureInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final path = options.path;
    final method = options.method;

    Object? data;
    int statusCode = 200;

    if (method == 'GET' && path == '/api/orders/REF/items') {
      data = <Map<String, dynamic>>[];
    } else if (method == 'PATCH' && path.startsWith('/api/orders/REF/items/')) {
      // Echo the incoming body back as a WorkItem-shaped JSON so the service
      // can deserialize the result.
      final body = options.data is Map ? options.data as Map : <String, dynamic>{};
      data = <String, dynamic>{
        'id': '1',
        'orderId': '1',
        'productName': 'Bánh kem',
        'blankId': body['blankId'],
      };
    } else {
      data = <String, dynamic>{};
    }

    handler.resolve(
      Response(requestOptions: options, statusCode: statusCode, data: data),
    );
  }
}

void main() {
  late WorkItemService service;
  late _CaptureInterceptor interceptor;

  setUp(() {
    interceptor = _CaptureInterceptor();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(interceptor);
    service = WorkItemService(dio);
  });

  group('updateWorkItem blankId', () {
    test('omits blankId when the parameter is left at unset', () async {
      await service.updateWorkItem('REF', '1', notes: 'x');

      final patch = interceptor.requests
          .firstWhere((r) => r.method == 'PATCH');
      expect(patch.data, isNot(contains('blankId')));
    });

    test('sends blankId when an int is provided', () async {
      await service.updateWorkItem('REF', '1', blankId: 5);

      final patch = interceptor.requests
          .firstWhere((r) => r.method == 'PATCH');
      expect(patch.data, containsPair('blankId', 5));
    });

    test('sends blankId: null to clear the assignment', () async {
      await service.updateWorkItem('REF', '1', blankId: null);

      final patch = interceptor.requests
          .firstWhere((r) => r.method == 'PATCH');
      expect(patch.data, containsPair('blankId', null));
    });

    test('deserializes blankId from the PATCH response', () async {
      final updated = await service.updateWorkItem('REF', '1', blankId: 7);

      expect(updated.blankId, 7);
    });

    test('deserializes null blankId when cleared', () async {
      final updated = await service.updateWorkItem('REF', '1', blankId: null);

      expect(updated.blankId, isNull);
    });
  });

  group('WorkItem.fromJson blankId', () {
    test('parses a provided blankId', () {
      final item = WorkItem.fromJson({
        'id': '9',
        'orderId': '2',
        'productName': 'Bánh mì',
        'blankId': 42,
      });
      expect(item.blankId, 42);
    });

    test('defaults to null when blankId is absent', () {
      final item = WorkItem.fromJson({
        'id': '9',
        'orderId': '2',
        'productName': 'Bánh mì',
      });
      expect(item.blankId, isNull);
    });
  });
}