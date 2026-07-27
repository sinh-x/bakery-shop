import 'package:bakery_app/data/api/work_item_service.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures requests and returns canned JSON for the relevant endpoints.
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
    } else if (method == 'PATCH' && path.contains('/blanks/')) {
      final body = options.data is Map ? options.data as Map : <String, dynamic>{};
      data = <String, dynamic>{
        'id': 100,
        'blankId': 7,
        'quantity': body['quantity'] ?? 1.0,
        'notes': body['notes'] ?? '',
      };
    } else if (method == 'PATCH' && path.startsWith('/api/orders/REF/items/')) {
      // Echo the incoming body back as a WorkItem-shaped JSON so the service
      // can deserialize the result.
      final body = options.data is Map ? options.data as Map : <String, dynamic>{};
      data = <String, dynamic>{
        'id': '1',
        'orderId': '1',
        'productName': 'Bánh kem',
        if (body.containsKey('notes')) 'notes': body['notes'],
      };
    } else if (method == 'POST' &&
        path.startsWith('/api/orders/REF/items/') &&
        path.endsWith('/blanks')) {
      final body = options.data is Map ? options.data as Map : <String, dynamic>{};
      data = <String, dynamic>{
        'id': 100,
        'blankId': body['blankId'],
        'quantity': body['quantity'],
        'notes': body['notes'],
      };
      statusCode = 201;
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

  group('updateWorkItem', () {
    test('omits blankId field entirely (removed in DG-294)', () async {
      await service.updateWorkItem('REF', '1', notes: 'x');

      final patch = interceptor.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.data, isNot(contains('blankId')));
    });
  });

  group('WorkItem.fromJson blanks', () {
    test('parses an empty blanks list when absent', () {
      final item = WorkItem.fromJson({
        'id': '9',
        'orderId': '2',
        'productName': 'Bánh mì',
      });
      expect(item.blanks, isEmpty);
    });

    test('parses a blanks array', () {
      final item = WorkItem.fromJson({
        'id': '9',
        'orderId': '2',
        'productName': 'Bánh mì',
        'blanks': [
          {'blankId': 1, 'quantity': 2.0, 'notes': 'ghi'},
          {'blankId': 3, 'quantity': 1.0, 'notes': ''},
        ],
      });
      expect(item.blanks.length, 2);
      expect(item.blanks.first.blankId, 1);
      expect(item.blanks.first.quantity, 2.0);
      expect(item.blanks.first.notes, 'ghi');
      expect(item.blanks.last.blankId, 3);
    });
  });

  group('addBlank', () {
    test('POSTs to the blanks sub-collection and returns the assignment', () async {
      final assignment = await service.addBlank(
        'REF',
        '1',
        blankId: 5,
        quantity: 3.0,
        notes: 'topper',
      );

      final post = interceptor.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, '/api/orders/REF/items/1/blanks');
      expect(post.data, {
        'blankId': 5,
        'quantity': 3.0,
        'notes': 'topper',
      });
      expect(assignment.id, 100);
      expect(assignment.blankId, 5);
      expect(assignment.quantity, 3.0);
      expect(assignment.notes, 'topper');
    });
  });

  group('updateBlank', () {
    test('PATCHes the blank assignment by id', () async {
      final updated = await service.updateBlank(
        'REF',
        '1',
        100,
        quantity: 5.0,
        notes: 'updated',
      );

      final patch = interceptor.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/api/orders/REF/items/1/blanks/100');
      expect(patch.data, {'quantity': 5.0, 'notes': 'updated'});
      expect(updated.quantity, 5.0);
      expect(updated.notes, 'updated');
    });

    test('omits fields that are not provided', () async {
      await service.updateBlank('REF', '1', 100, quantity: 5.0);

      final patch = interceptor.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.data, {'quantity': 5.0});
    });
  });

  group('deleteBlank', () {
    test('DELETEs the blank assignment by id', () async {
      await service.deleteBlank('REF', '1', 100);

      final delete = interceptor.requests.firstWhere((r) => r.method == 'DELETE');
      expect(delete.path, '/api/orders/REF/items/1/blanks/100');
    });
  });
}