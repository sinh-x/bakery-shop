import 'package:bakery_app/data/api/audit_log_service.dart';
import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/providers/audit_log_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a list of N audit-log entries as the backend would return them.
Map<String, dynamic> _pageResponse({
  required int page,
  required int pageSize,
  required int total,
}) {
  final remaining = total - (page - 1) * pageSize;
  final count = remaining < pageSize ? remaining : pageSize;
  final items = List.generate(
    count < 0 ? 0 : count,
    (i) => <String, dynamic>{
      'id': (page - 1) * pageSize + i + 1,
      'username': 'Sinh',
      'action': 'create',
      'entity_type': 'config',
      'entity_id': 'id-${(page - 1) * pageSize + i + 1}',
      'old_value': null,
      'new_value': '{"v": ${i + 1}}',
      'created_at': '2026-07-14T10:00:0${i}Z',
    },
  );
  return <String, dynamic>{
    'items': items,
    'page': page,
    'page_size': pageSize,
    'total': total,
  };
}

/// A Dio interceptor that serves audit-log responses for any page size, and
/// records the query params used so tests can assert on filters.
class _PagingInterceptor extends Interceptor {
  _PagingInterceptor({this.total = 60, this.pageSize = 50});

  final int total;
  final int pageSize;

  final List<Map<String, dynamic>> capturedParams = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedParams.add(Map<String, dynamic>.from(options.queryParameters));
    final page = (options.queryParameters['page'] as num?)?.toInt() ?? 1;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: _pageResponse(page: page, pageSize: pageSize, total: total),
      ),
    );
  }
}

void main() {
  group('AuditLogNotifier', () {
    test('build() fetches the first page with empty filters', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_PagingInterceptor());
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      // Wait for the AsyncNotifier to resolve.
      await container.read(auditLogProvider.future);

      final state = container.read(auditLogProvider).value!;
      expect(state.page, 1);
      expect(state.items, hasLength(50));
      expect(state.total, 60);
      expect(state.hasMore, isTrue);
    });

    test('applyFilters() re-queries with the given filters from page 1',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_PagingInterceptor());
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(auditLogProvider.future);
      final interceptor = dio.interceptors.whereType<_PagingInterceptor>().first;

      // Reset captured params to make the assertion unambiguous.
      interceptor.capturedParams.clear();

      await container.read(auditLogProvider.notifier).applyFilters(
            const AuditLogFilters(
              username: 'An',
              entityType: 'product',
              dateFrom: '2026-07-01',
              dateTo: '2026-07-10',
            ),
          );

      final state = container.read(auditLogProvider).value!;
      expect(state.page, 1);
      expect(state.filters.username, 'An');
      expect(state.filters.entityType, 'product');
      expect(state.filters.dateFrom, '2026-07-01');
      expect(state.filters.dateTo, '2026-07-10');

      // Exactly one query, with all four filters + page=1.
      expect(interceptor.capturedParams, hasLength(1));
      expect(interceptor.capturedParams.first['username'], 'An');
      expect(interceptor.capturedParams.first['entity_type'], 'product');
      expect(interceptor.capturedParams.first['date_from'], '2026-07-01');
      expect(interceptor.capturedParams.first['date_to'], '2026-07-10');
      expect(interceptor.capturedParams.first['page'], 1);
    });

    test('loadMore() appends the next page and updates hasMore', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_PagingInterceptor(total: 60, pageSize: 50));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(auditLogProvider.future);
      expect(container.read(auditLogProvider).value!.items, hasLength(50));
      expect(container.read(auditLogProvider).value!.hasMore, isTrue);

      await container.read(auditLogProvider.notifier).loadMore();

      final state = container.read(auditLogProvider).value!;
      expect(state.page, 2);
      expect(state.items, hasLength(60));
      expect(state.hasMore, isFalse);
    });

    test('loadMore() is a no-op when hasMore is false', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_PagingInterceptor(total: 5, pageSize: 50));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(auditLogProvider.future);
      final stateBefore = container.read(auditLogProvider).value!;
      expect(stateBefore.hasMore, isFalse);
      expect(stateBefore.items, hasLength(5));

      await container.read(auditLogProvider.notifier).loadMore();

      final stateAfter = container.read(auditLogProvider).value!;
      expect(stateAfter.page, 1);
      expect(stateAfter.items, hasLength(5));
    });

    test('clearFilters() resets to empty filters and re-queries', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_PagingInterceptor());
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(auditLogProvider.future);
      await container
          .read(auditLogProvider.notifier)
          .applyFilters(const AuditLogFilters(username: 'An'));

      expect(container.read(auditLogProvider).value!.filters.username, 'An');

      await container.read(auditLogProvider.notifier).clearFilters();
      final state = container.read(auditLogProvider).value!;
      expect(state.filters, const AuditLogFilters());
      expect(state.page, 1);
    });
  });
}