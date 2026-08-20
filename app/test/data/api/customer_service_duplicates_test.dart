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

class _BatchMergeInterceptor extends Interceptor {
  _BatchMergeInterceptor(this._response);
  final Map<String, dynamic> _response;
  BatchMergeRequestRecord? lastRequest;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final match = RegExp(r'^/api/customers/(\d+)/batch-merge$').firstMatch(
      options.path,
    );
    if (match != null && options.method == 'POST') {
      final targetId = int.parse(match.group(1)!);
      lastRequest = BatchMergeRequestRecord(
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

class BatchMergeRequestRecord {
  BatchMergeRequestRecord({required this.targetId, required this.body});
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
        'recomputedYears': [2025, 2026],
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
      expect(result.recomputedYears, [2025, 2026]);

      expect(interceptor.lastRequest, isNotNull);
      expect(interceptor.lastRequest!.targetId, 1);
      expect(interceptor.lastRequest!.body['sourceCustomerId'], 2);
    });
  });

  group('CustomerService.batchMergeCustomers', () {
    test('POSTs sourceCustomerIds and parses batch merge result', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _BatchMergeInterceptor({
        'ok': true,
        'targetId': 1,
        'sourceIds': [2, 3],
        'customer': {
          'id': 1,
          'name': 'Sinh',
          'phone': '0901234567',
          'phones': [
            {'phone': '0901234567', 'isPrimary': true},
            {'phone': '0912345678', 'isPrimary': false},
          ],
        },
        'merged': [
          {
            'sourceId': 2,
            'movedOrders': 2,
            'addedPhones': 1,
            'recomputedYears': [2025, 2026],
          },
          {
            'sourceId': 3,
            'movedOrders': 1,
            'addedPhones': 0,
            'recomputedYears': [2025],
          },
        ],
        'totalMovedOrders': 3,
        'totalAddedPhones': 1,
        'recomputedYears': [2025, 2026],
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.batchMergeCustomers(
        targetId: 1,
        sourceCustomerIds: [2, 3],
      );

      expect(result.ok, true);
      expect(result.targetId, 1);
      expect(result.sourceIds, [2, 3]);
      expect(result.customer.id, 1);
      expect(result.customer.name, 'Sinh');
      expect(result.customer.phones.length, 2);
      expect(result.customer.phones.first.phone, '0901234567');
      expect(result.customer.phones.first.isPrimary, true);
      expect(result.merged.length, 2);
      expect(result.merged.first.sourceId, 2);
      expect(result.merged.first.movedOrders, 2);
      expect(result.merged.first.addedPhones, 1);
      expect(result.merged.first.recomputedYears, [2025, 2026]);
      expect(result.merged.last.sourceId, 3);
      expect(result.merged.last.movedOrders, 1);
      expect(result.merged.last.addedPhones, 0);
      expect(result.merged.last.recomputedYears, [2025]);
      expect(result.totalMovedOrders, 3);
      expect(result.totalAddedPhones, 1);
      expect(result.recomputedYears, [2025, 2026]);

      expect(interceptor.lastRequest, isNotNull);
      expect(interceptor.lastRequest!.targetId, 1);
      expect(interceptor.lastRequest!.body['sourceCustomerIds'], [2, 3]);
    });

    test('parses empty merged list and single source batch', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _BatchMergeInterceptor({
        'ok': true,
        'targetId': 10,
        'sourceIds': [11],
        'customer': {'id': 10, 'name': 'Target', 'phone': '', 'phones': const []},
        'merged': const [],
        'totalMovedOrders': 0,
        'totalAddedPhones': 0,
        'recomputedYears': const [],
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.batchMergeCustomers(
        targetId: 10,
        sourceCustomerIds: [11],
      );

      expect(result.ok, true);
      expect(result.targetId, 10);
      expect(result.sourceIds, [11]);
      expect(result.merged, isEmpty);
      expect(result.totalMovedOrders, 0);
      expect(result.totalAddedPhones, 0);
      expect(result.recomputedYears, isEmpty);
      expect(interceptor.lastRequest!.body['sourceCustomerIds'], [11]);
    });

    test('tolerates missing optional fields (defensive defaults)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _BatchMergeInterceptor(<String, dynamic>{
        'ok': true,
        'targetId': 1,
        'customer': {'id': 1, 'name': 'Sinh'},
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(customerServiceProvider);
      final result = await service.batchMergeCustomers(
        targetId: 1,
        sourceCustomerIds: [2],
      );

      expect(result.ok, true);
      expect(result.targetId, 1);
      expect(result.sourceIds, isEmpty);
      expect(result.merged, isEmpty);
      expect(result.totalMovedOrders, 0);
      expect(result.totalAddedPhones, 0);
      expect(result.recomputedYears, isEmpty);
      expect(result.customer.id, 1);
      expect(result.customer.name, 'Sinh');
    });
  });
}