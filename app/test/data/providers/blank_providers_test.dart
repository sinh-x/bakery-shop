import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/providers/blank_demand_provider.dart';
import 'package:bakery_app/data/providers/blank_stock_provider.dart';
import 'package:bakery_app/data/providers/blanks_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Routing interceptor that serves canned responses based on request method
/// and path. Each call records the request so tests can assert on it.
class _BlankApiInterceptor extends Interceptor {
  _BlankApiInterceptor({
    this.blanks = const [],
    this.stock = const [],
    this.demand = const [],
    this.createdBlank,
    this.createdStockEntry,
  });

  final List<Map<String, dynamic>> blanks;
  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> demand;
  final Map<String, dynamic>? createdBlank;
  final Map<String, dynamic>? createdStockEntry;

  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final path = options.path;
    final method = options.method;

    Object? data;
    int statusCode = 200;

    if (path == '/api/blanks' && method == 'GET') {
      data = blanks;
    } else if (path == '/api/blanks' && method == 'POST') {
      data = createdBlank ?? {};
      statusCode = 201;
    } else if (path.startsWith('/api/blanks/') && method == 'PATCH') {
      data = createdBlank ?? {};
    } else if (path.startsWith('/api/blanks/') && method == 'DELETE') {
      data = <String, dynamic>{};
      statusCode = 204;
    } else if (path == '/api/blanks/stock' && method == 'GET') {
      data = stock;
    } else if (path == '/api/blanks/stock' && method == 'POST') {
      data = createdStockEntry ?? {};
      statusCode = 201;
    } else if (path == '/api/blanks/demand' && method == 'GET') {
      data = demand;
    } else {
      data = <String, dynamic>{};
    }

    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: statusCode,
        data: data,
      ),
    );
  }
}

Map<String, dynamic> _blankJson({
  int id = 1,
  String name = 'Phôi cốt',
  String category = 'cot',
  String unit = 'cai',
  String notes = '',
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'notes': notes,
      'createdAt': '2026-07-24T10:00:00Z',
      'updatedAt': '2026-07-24T10:00:00Z',
    };

Map<String, dynamic> _stockSummaryJson({
  int blankId = 1,
  String name = 'Phôi cốt',
  double stock = 12.0,
}) =>
    {
      'blankId': blankId,
      'name': name,
      'category': 'cot',
      'unit': 'cai',
      'stock': stock,
    };

Map<String, dynamic> _demandJson({
  int blankId = 1,
  String name = 'Phôi cốt',
  double demand = 20.0,
  double stock = 12.0,
  double shortage = 8.0,
}) =>
    {
      'blankId': blankId,
      'name': name,
      'category': 'cot',
      'unit': 'cai',
      'demand': demand,
      'stock': stock,
      'shortage': shortage,
    };

Map<String, dynamic> _stockEntryJson({int id = 7, int blankId = 1}) => {
      'id': id,
      'blankId': blankId,
      'quantity': 10.0,
      'producedDate': '2026-07-24',
      'expiryDate': null,
      'type': 'production',
      'createdAt': '2026-07-24T10:00:00Z',
    };

ProviderContainer _container(_BlankApiInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  return ProviderContainer(
    overrides: [dioProvider.overrideWithValue(dio)],
  );
}

void main() {
  group('BlanksNotifier', () {
    test('build() fetches all blanks via GET /api/blanks', () async {
      final interceptor = _BlankApiInterceptor(
        blanks: [_blankJson(id: 1), _blankJson(id: 2, name: 'Phôi kem')],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      final blanks = await container.read(blanksProvider.future);

      expect(blanks, hasLength(2));
      expect(blanks.first.id, 1);
      expect(blanks.last.name, 'Phôi kem');
    });

    test('refresh() reloads the list', () async {
      final interceptor = _BlankApiInterceptor(blanks: [_blankJson()]);
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);
      interceptor.blanks.clear();
      interceptor.blanks
          .addAll([_blankJson(id: 5), _blankJson(id: 6, name: 'Phôi mới')]);

      await container.read(blanksProvider.notifier).refresh();

      final blanks = container.read(blanksProvider).value!;
      expect(blanks, hasLength(2));
      expect(blanks.first.id, 5);
    });

    test('createBlank POSTs then refreshes the list', () async {
      final interceptor = _BlankApiInterceptor(
        blanks: [_blankJson(id: 1)],
        createdBlank: _blankJson(id: 2, name: 'Phôi kem'),
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);
      interceptor.blanks.add(_blankJson(id: 2, name: 'Phôi kem'));

      await container
          .read(blanksProvider.notifier)
          .createBlank(name: 'Phôi kem', category: 'kem');

      // POST then GET happened.
      final methods = interceptor.requests.map((r) => r.method).toList();
      expect(methods, contains('POST'));
      expect(methods.where((m) => m == 'GET').length, greaterThanOrEqualTo(2));

      final blanks = container.read(blanksProvider).value!;
      expect(blanks, hasLength(2));
      expect(blanks.any((b) => b.name == 'Phôi kem'), isTrue);
    });

    test('updateBlank PATCHes then refreshes the list', () async {
      final interceptor = _BlankApiInterceptor(
        blanks: [_blankJson(id: 1, notes: '')],
        createdBlank: _blankJson(id: 1, notes: 'updated'),
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);
      interceptor.blanks.first['notes'] = 'updated';

      await container
          .read(blanksProvider.notifier)
          .updateBlank(1, notes: 'updated');

      final patchReq = interceptor.requests.firstWhere(
        (r) => r.method == 'PATCH',
      );
      expect(patchReq.path, '/api/blanks/1');
      expect(patchReq.data, containsPair('notes', 'updated'));

      final blanks = container.read(blanksProvider).value!;
      expect(blanks.first.notes, 'updated');
    });

    test('deleteBlank issues DELETE then refreshes the list', () async {
      final interceptor = _BlankApiInterceptor(
        blanks: [_blankJson(id: 1), _blankJson(id: 2)],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);
      interceptor.blanks.removeWhere((b) => b['id'] == 1);

      await container.read(blanksProvider.notifier).deleteBlank(1);

      final deleteReq = interceptor.requests.firstWhere(
        (r) => r.method == 'DELETE',
      );
      expect(deleteReq.path, '/api/blanks/1');

      final blanks = container.read(blanksProvider).value!;
      expect(blanks, hasLength(1));
      expect(blanks.first.id, 2);
    });

    test('filterByCategory forwards category query param', () async {
      final interceptor = _BlankApiInterceptor(
        blanks: [_blankJson(id: 1, category: 'kem')],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);

      await container.read(blanksProvider.notifier).filterByCategory('kem');

      final getReq = interceptor.requests
          .where((r) => r.method == 'GET' && r.path == '/api/blanks')
          .last;
      expect(getReq.queryParameters, containsPair('category', 'kem'));
    });

    test('filterByCategory with empty value clears the filter', () async {
      final interceptor = _BlankApiInterceptor(blanks: [_blankJson()]);
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blanksProvider.future);
      await container.read(blanksProvider.notifier).filterByCategory('');

      final getReq = interceptor.requests
          .where((r) => r.method == 'GET' && r.path == '/api/blanks')
          .last;
      // No category param sent when filter cleared.
      expect(getReq.queryParameters.containsKey('category'), isFalse);
    });
  });

  group('BlankStockNotifier', () {
    test('build() fetches stock via GET /api/blanks/stock', () async {
      final interceptor = _BlankApiInterceptor(
        stock: [_stockSummaryJson(blankId: 1, stock: 12.0)],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      final stock = await container.read(blankStockProvider.future);

      expect(stock, hasLength(1));
      expect(stock.first.blankId, 1);
      expect(stock.first.stock, 12.0);
    });

    test('refresh() reloads the stock overview', () async {
      final interceptor = _BlankApiInterceptor(
        stock: [_stockSummaryJson(blankId: 1, stock: 5.0)],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blankStockProvider.future);
      interceptor.stock.first['stock'] = 15.0;

      await container.read(blankStockProvider.notifier).refresh();

      expect(container.read(blankStockProvider).value!.first.stock, 15.0);
    });

    test('recordProduction POSTs production type and refreshes', () async {
      final interceptor = _BlankApiInterceptor(
        stock: [_stockSummaryJson(blankId: 1, stock: 12.0)],
        createdStockEntry: _stockEntryJson(),
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blankStockProvider.future);
      interceptor.stock.first['stock'] = 22.0;

      await container.read(blankStockProvider.notifier).recordProduction(
        1,
        10.0,
        producedDate: '2026-07-24',
        expiryDate: '2026-07-31',
      );

      final postReq = interceptor.requests.firstWhere(
        (r) => r.method == 'POST' && r.path == '/api/blanks/stock',
      );
      expect(postReq.data, containsPair('blankId', 1));
      expect(postReq.data, containsPair('quantity', 10.0));
      expect(postReq.data, containsPair('type', 'production'));

      expect(container.read(blankStockProvider).value!.first.stock, 22.0);
    });

    test('recordUsage POSTs usage type and refreshes', () async {
      final interceptor = _BlankApiInterceptor(
        stock: [_stockSummaryJson(blankId: 1, stock: 12.0)],
        createdStockEntry: _stockEntryJson(),
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blankStockProvider.future);
      interceptor.stock.first['stock'] = 9.0;

      await container.read(blankStockProvider.notifier).recordUsage(
        1,
        3.0,
      );

      final postReq = interceptor.requests.firstWhere(
        (r) => r.method == 'POST' && r.path == '/api/blanks/stock',
      );
      expect(postReq.data, containsPair('type', 'usage'));
      expect(postReq.data, containsPair('quantity', 3.0));

      expect(container.read(blankStockProvider).value!.first.stock, 9.0);
    });
  });

  group('BlankDemandNotifier', () {
    test('build() fetches demand via GET /api/blanks/demand', () async {
      final interceptor = _BlankApiInterceptor(
        demand: [
          _demandJson(blankId: 1, demand: 20.0, stock: 12.0, shortage: 8.0),
        ],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      final demand = await container.read(blankDemandProvider.future);

      expect(demand, hasLength(1));
      expect(demand.first.blankId, 1);
      expect(demand.first.demand, 20.0);
      expect(demand.first.shortage, 8.0);
    });

    test('refresh() reloads the demand overview', () async {
      final interceptor = _BlankApiInterceptor(
        demand: [_demandJson(blankId: 1, shortage: 8.0)],
      );
      final container = _container(interceptor);
      addTearDown(container.dispose);

      await container.read(blankDemandProvider.future);
      interceptor.demand.first['shortage'] = 0.0;

      await container.read(blankDemandProvider.notifier).refresh();

      expect(container.read(blankDemandProvider).value!.first.shortage, 0.0);
    });
  });
}