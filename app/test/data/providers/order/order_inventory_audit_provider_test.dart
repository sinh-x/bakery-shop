import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/providers/order/order_inventory_audit_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry(int id, String operationId) => <String, dynamic>{
  'id': id,
  'operationId': operationId,
  'orderId': 1,
  'orderRef': 'ORD-1',
  'trigger': 'status_action',
  'action': 'inventory_deduct',
  'statusBefore': 'new',
  'statusAfter': 'confirmed',
  'actor': <String, dynamic>{
    'identifier': 'cashier',
    'username': 'cashier',
    'staffId': 3,
    'staffName': 'Thu ngân',
    'role': 'staff',
  },
  'createdAt': '2026-09-04T03:00:0${id}Z',
  'outcome': 'applied',
  'reasonCode': 'eligible_display_item',
  'detail': null,
  'item': <String, dynamic>{},
  'requestedDelta': -1,
  'appliedDelta': -1,
  'before': <String, dynamic>{'fifoAvailable': 2, 'negative': 0, 'net': 2},
  'after': <String, dynamic>{'fifoAvailable': 1, 'negative': 0, 'net': 1},
  'stockMovementId': id,
  'negativeMovementId': null,
  'relatedEntryId': null,
  'reconciliationSessionId': null,
  'reconciliationSessionIds': <int>[],
  'reconciliationLineIds': <int>[],
  'reconciliationSaleRowIds': <int>[],
};

Map<String, dynamic> _page({
  required List<Map<String, dynamic>> items,
  required int total,
  required bool hasMore,
  int offset = 0,
}) => <String, dynamic>{
  'items': items,
  'total': total,
  'hasMore': hasMore,
  'limit': 100,
  'offset': offset,
};

class _QueuedInterceptor extends Interceptor {
  _QueuedInterceptor(this.responses);

  final List<Object> responses;
  final List<Map<String, dynamic>> queries = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    queries.add(Map<String, dynamic>.from(options.queryParameters));
    final response = responses.removeAt(0);
    if (response is DioException) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: response as Map<String, dynamic>,
      ),
    );
  }
}

DioException _failure() => DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.connectionError,
);

ProviderContainer _container(_QueuedInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  return ProviderContainer(
    overrides: [orderServiceProvider.overrideWithValue(OrderService(dio))],
  );
}

void main() {
  test('is lazy and fetches default first page only when requested', () async {
    final interceptor = _QueuedInterceptor([
      _page(items: [_entry(2, 'op-2')], total: 1, hasMore: false),
    ]);
    final container = _container(interceptor);
    addTearDown(container.dispose);
    final provider = orderInventoryAuditProvider('ORD-1');

    final initial = await container.read(provider.future);
    expect(initial.initialized, isFalse);
    expect(interceptor.queries, isEmpty);

    await container.read(provider.notifier).loadFirstPage();
    expect(container.read(provider).value!.items.single.id, 2);
    expect(interceptor.queries.single, <String, dynamic>{
      'limit': 100,
      'offset': 0,
    });
    await container.read(provider.notifier).loadFirstPage();
    expect(interceptor.queries, hasLength(1));
  });

  test('supports initial error and retry to an empty envelope', () async {
    final interceptor = _QueuedInterceptor([
      _failure(),
      _page(items: [], total: 0, hasMore: false),
    ]);
    final container = _container(interceptor);
    addTearDown(container.dispose);
    final provider = orderInventoryAuditProvider('ORD-1');
    await container.read(provider.future);

    await container.read(provider.notifier).loadFirstPage();
    expect(container.read(provider).hasError, isTrue);
    await container.read(provider.notifier).retry();
    expect(container.read(provider).value!.initialized, isTrue);
    expect(container.read(provider).value!.items, isEmpty);
  });

  test('retains rendered entries when refresh fails', () async {
    final interceptor = _QueuedInterceptor([
      _page(items: [_entry(2, 'op-2')], total: 1, hasMore: false),
      _failure(),
    ]);
    final container = _container(interceptor);
    addTearDown(container.dispose);
    final provider = orderInventoryAuditProvider('ORD-1');
    await container.read(provider.future);
    await container.read(provider.notifier).loadFirstPage();

    await container.read(provider.notifier).refresh();
    final state = container.read(provider).value!;
    expect(state.items.single.id, 2);
    expect(state.laterRequestFailed, isTrue);
    expect(state.loadMoreFailed, isFalse);
  });

  test(
    'loads more in API order and retries without discarding pages',
    () async {
      final interceptor = _QueuedInterceptor([
        _page(items: [_entry(2, 'op')], total: 2, hasMore: true),
        _failure(),
        _page(items: [_entry(1, 'op')], total: 2, hasMore: false, offset: 1),
      ]);
      final container = _container(interceptor);
      addTearDown(container.dispose);
      final provider = orderInventoryAuditProvider('ORD-1');
      await container.read(provider.future);
      await container.read(provider.notifier).loadFirstPage();

      await container.read(provider.notifier).loadMore();
      expect(container.read(provider).value!.items.map((item) => item.id), [2]);
      expect(container.read(provider).value!.loadMoreFailed, isTrue);

      await container.read(provider.notifier).retryRetainedFailure();
      final state = container.read(provider).value!;
      expect(state.items.map((item) => item.id), [2, 1]);
      expect(state.hasMore, isFalse);
      expect(interceptor.queries.last['offset'], 1);
    },
  );
}
