import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/customer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DuplicateInterceptor extends Interceptor {
  _DuplicateInterceptor(this._duplicates);

  final Map<String, dynamic> _duplicates;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (options.path == '/api/customers/duplicates' &&
        options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: _duplicates,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class _MergeInterceptor extends Interceptor {
  _MergeInterceptor(this._response);

  final Map<String, dynamic> _response;
  MergeRequestRecord? lastRequest;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final match = RegExp(r'^/api/customers/(\d+)/merge$').firstMatch(
      options.path,
    );
    if (match != null && options.method == 'POST') {
      final targetId = int.parse(match.group(1)!);
      lastRequest = MergeRequestRecord(
        targetId: targetId,
        body: options.data as Map<String, dynamic>? ?? const {},
      );
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: _response,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class MergeRequestRecord {
  MergeRequestRecord({required this.targetId, required this.body});
  final int targetId;
  final Map<String, dynamic> body;
}

void main() {
  group('CustomerService.listDuplicates', () {
    test('parses groups with phone and name kinds + order counts', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(
        _DuplicateInterceptor({
          'groups': [
            {
              'key': '0901234567',
              'kind': 'phone',
              'customers': [
                {'id': 1, 'name': 'Sinh', 'phone': '0901234567', 'orderCount': 5},
                {'id': 2, 'name': 'Sinh A', 'phone': '0901234567', 'orderCount': 2},
              ],
            },
            {
              'key': 'nguyen van a',
              'kind': 'name',
              'customers': [
                {'id': 3, 'name': 'Nguyễn Văn A', 'phone': '', 'orderCount': 0},
                {'id': 4, 'name': 'Nguyễn Văn Á', 'phone': '091', 'orderCount': 1},
              ],
            },
          ],
        }),
      );
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.listDuplicates();

      expect(result.groups.length, 2);
      final phoneGroup = result.groups.first;
      expect(phoneGroup.kind, 'phone');
      expect(phoneGroup.key, '0901234567');
      expect(phoneGroup.customers.length, 2);
      expect(phoneGroup.customers.first.id, 1);
      expect(phoneGroup.customers.first.orderCount, 5);
      final nameGroup = result.groups.last;
      expect(nameGroup.kind, 'name');
      expect(nameGroup.customers.last.phone, '091');
      expect(nameGroup.customers.last.orderCount, 1);
    });

    test('handles empty groups list', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(
        _DuplicateInterceptor({'groups': const []}),
      );
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.listDuplicates();
      expect(result.groups, isEmpty);
    });
  });

  group('CustomerService.mergeCustomers', () {
    test('POSTs sourceCustomerId and parses merge result', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _MergeInterceptor({
        'ok': true,
        'targetId': 1,
        'sourceId': 2,
        'customer': {'id': 1, 'name': 'Sinh', 'phone': '0901234567'},
        'movedOrders': 2,
        'addedPhones': 1,
        'recomputedYears': 1,
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.mergeCustomers(targetId: 1, sourceId: 2);

      expect(result.ok, true);
      expect(result.targetId, 1);
      expect(result.sourceId, 2);
      expect(result.customer.id, 1);
      expect(result.customer.name, 'Sinh');
      expect(result.movedOrders, 2);
      expect(result.addedPhones, 1);
      expect(result.recomputedYears, 1);

      expect(interceptor.lastRequest, isNotNull);
      expect(interceptor.lastRequest!.targetId, 1);
      expect(interceptor.lastRequest!.body['sourceCustomerId'], 2);
    });
  });
}