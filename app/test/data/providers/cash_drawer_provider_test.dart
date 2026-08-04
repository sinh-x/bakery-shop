import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/cash_drawer_service.dart';
import 'package:bakery_app/providers/cash_drawer_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interceptor that serves a fixed JSON body for every request and records
/// the request path + query so provider tests can assert on the wiring.
class _StubInterceptor extends Interceptor {
  _StubInterceptor(this.responseData);

  final dynamic responseData;
  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastQuery = options.queryParameters;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: responseData,
      ),
    );
  }
}

Map<String, dynamic> _drawerJson({
  String id = '1',
  String status = 'open',
  int expectedBalance = 1550000,
}) {
  return {
    'id': id,
    'openedAt': '2026-08-01T00:00:00Z',
    'closedAt': null,
    'status': status,
    'openingBalance': 1000000,
    'countedAmount': null,
    'discrepancy': null,
    'expectedBalance': expectedBalance,
  };
}

void main() {
  group('cashDrawerStatusProvider (DG-324 Phase 4)', () {
    test('fetches GET /api/cash-drawer/status and returns the active drawer',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_StubInterceptor(_drawerJson()));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final drawer = await container.read(cashDrawerStatusProvider.future);

      expect(drawer, isNotNull);
      expect(drawer!.id, '1');
      expect(drawer.isOpen, isTrue);
      expect(drawer.expectedBalance, 1550000);

      final interceptor = dio.interceptors.whereType<_StubInterceptor>().first;
      expect(interceptor.lastPath, '/api/cash-drawer/status');
    });

    test('returns null when no drawer is open', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_StubInterceptor(null));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final drawer = await container.read(cashDrawerStatusProvider.future);
      expect(drawer, isNull);
    });
  });

  group('cashDrawerHistoryProvider (DG-324 Phase 4)', () {
    test('fetches GET /api/cash-drawer/history with the given filter', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_StubInterceptor({
          'total': 2,
          'limit': 50,
          'offset': 0,
          'items': [
            _drawerJson(id: '1', status: 'closed'),
            _drawerJson(id: '2', status: 'closed'),
          ],
        }));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final resp = await container.read(
        cashDrawerHistoryProvider(
          const CashDrawerHistoryFilter(
            since: '2026-08-01',
            until: '2026-08-31',
          ),
        ).future,
      );

      expect(resp.total, 2);
      expect(resp.items, hasLength(2));
      expect(resp.items.first.id, '1');
      expect(resp.items.first.isClosed, isTrue);

      final interceptor = dio.interceptors.whereType<_StubInterceptor>().first;
      expect(interceptor.lastPath, '/api/cash-drawer/history');
      expect(interceptor.lastQuery!['since'], '2026-08-01');
      expect(interceptor.lastQuery!['until'], '2026-08-31');
    });

    test('caches distinct filters independently (family semantics)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_StubInterceptor({
          'total': 0,
          'limit': 50,
          'offset': 0,
          'items': <Map<String, dynamic>>[],
        }));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      // Two different filters should both resolve without error.
      final a = await container.read(
        cashDrawerHistoryProvider(const CashDrawerHistoryFilter()).future,
      );
      final b = await container.read(
        cashDrawerHistoryProvider(
          const CashDrawerHistoryFilter(since: '2026-08-01'),
        ).future,
      );

      expect(a.total, 0);
      expect(b.total, 0);
    });
  });

  group('CashDrawerHistoryFilter', () {
    test('equality + hashCode account for all fields', () {
      const a = CashDrawerHistoryFilter(since: '2026-08-01', limit: 10);
      const b = CashDrawerHistoryFilter(since: '2026-08-01', limit: 10);
      const c = CashDrawerHistoryFilter(since: '2026-08-02', limit: 10);

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('copyWith preserves unspecified fields', () {
      const original = CashDrawerHistoryFilter(since: '2026-08-01', limit: 25);
      final updated = original.copyWith(offset: 50);

      expect(updated.since, '2026-08-01');
      expect(updated.limit, 25);
      expect(updated.offset, 50);
    });
  });

  group('cashDrawerServiceProvider wiring', () {
    test('can be overridden in a ProviderContainer', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_StubInterceptor(_drawerJson()));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      // Reading the service provider builds a CashDrawerService bound to the
      // overridden Dio. Confirm it is the expected type and works end-to-end.
      final service = container.read(cashDrawerServiceProvider);
      expect(service, isA<CashDrawerService>());

      final drawer = await service.getDrawerStatus();
      expect(drawer, isNotNull);
      expect(drawer!.id, '1');
    });
  });
}