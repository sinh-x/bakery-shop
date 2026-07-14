import 'package:bakery_app/data/api/audit_log_service.dart';
import 'package:bakery_app/data/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditLogService', () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
    });

    test('list() returns parsed AuditLogPage with items and metadata', () async {
      dio.interceptors.add(
        _AuditLogInterceptor({
          '/api/audit-log': Response(
            requestOptions: RequestOptions(path: '/api/audit-log'),
            statusCode: 200,
            data: <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 1,
                  'username': 'Sinh',
                  'action': 'create',
                  'entity_type': 'config',
                  'entity_id': 'order_source:in_store',
                  'old_value': null,
                  'new_value': '{"value": "in_store"}',
                  'created_at': '2026-07-14T10:00:00Z',
                },
                <String, dynamic>{
                  'id': 2,
                  'username': 'An',
                  'action': 'update',
                  'entity_type': 'product',
                  'entity_id': 42,
                  'old_value': '{"price": 100}',
                  'new_value': '{"price": 120}',
                  'created_at': '2026-07-14T11:00:00Z',
                },
              ],
              'page': 1,
              'page_size': 50,
              'total': 2,
            },
          ),
        }),
      );
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(auditLogServiceProvider);
      final page = await service.list(page: 1);

      expect(page.items, hasLength(2));
      expect(page.page, 1);
      expect(page.pageSize, 50);
      expect(page.total, 2);
      expect(page.totalPages, 1);

      final first = page.items.first;
      expect(first.id, 1);
      expect(first.username, 'Sinh');
      expect(first.action, 'create');
      expect(first.entityType, 'config');
      expect(first.entityId, 'order_source:in_store');
      expect(first.oldValue, isNull);
      expect(first.newValue, '{"value": "in_store"}');

      final second = page.items.last;
      expect(second.entityId, '42');
      expect(second.action, 'update');
      expect(second.entityType, 'product');
    });

    test('list() passes filters and pagination as query params (FR23/FR24)',
        () async {
      final captured = <Map<String, dynamic>>[];
      dio.interceptors.add(
        _CaptureInterceptor('/api/audit-log', captured),
      );
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(auditLogServiceProvider);
      await service.list(
        filters: const AuditLogFilters(
          username: 'Sinh',
          entityType: 'config',
          dateFrom: '2026-07-01',
          dateTo: '2026-07-31',
        ),
        page: 3,
        pageSize: 25,
      );

      expect(captured, hasLength(1));
      final params = captured.first;
      expect(params['username'], 'Sinh');
      expect(params['entity_type'], 'config');
      expect(params['date_from'], '2026-07-01');
      expect(params['date_to'], '2026-07-31');
      expect(params['page'], 3);
      expect(params['page_size'], 25);
    });

    test('AuditLogFilters.toQueryParams omits empty filters', () {
      const filters = AuditLogFilters();
      final params = filters.toQueryParams(page: 1, pageSize: 50);
      expect(params['page'], 1);
      expect(params['page_size'], 50);
      expect(params.containsKey('username'), isFalse);
      expect(params.containsKey('entity_type'), isFalse);
      expect(params.containsKey('date_from'), isFalse);
      expect(params.containsKey('date_to'), isFalse);
    });

    test('AuditLogPage.totalPages computes ceiling of total/pageSize', () {
      final page = AuditLogPage(items: [], page: 1, pageSize: 50, total: 101);
      expect(page.totalPages, 3);
    });
  });
}

class _AuditLogInterceptor extends Interceptor {
  _AuditLogInterceptor(this.responses);

  final Map<String, Response<dynamic>> responses;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final response = responses[options.path];
    if (response != null) {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: response.statusCode ?? 200,
          data: response.data,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class _CaptureInterceptor extends Interceptor {
  _CaptureInterceptor(this.path, this.captured);

  final String path;
  final List<Map<String, dynamic>> captured;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == path) {
      captured.add(Map<String, dynamic>.from(options.queryParameters));
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'items': <Map<String, dynamic>>[],
          'page': 1,
          'page_size': 50,
          'total': 0,
        },
      ),
    );
  }
}