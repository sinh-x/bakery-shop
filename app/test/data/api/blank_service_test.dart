import 'package:bakery_app/data/api/blank_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the most recent request (method, path, query, body) and returns
/// a canned [response] (defaults to empty map).
class _RecordingInterceptor extends Interceptor {
  String? method;
  String? path;
  Map<String, dynamic>? query;
  Map<String, dynamic>? body;
  Object response;

  _RecordingInterceptor(this.response);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    method = options.method;
    path = options.path;
    query = Map<String, dynamic>.from(options.queryParameters);
    body = options.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(options.data as Map)
        : null;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: response,
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
  String createdAt = '2026-07-24T10:00:00Z',
  String updatedAt = '2026-07-24T10:00:00Z',
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
    'unit': unit,
    'notes': notes,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

Map<String, dynamic> _bomJson({
  int id = 1,
  int blankId = 2,
  int priceChipId = 5,
  int? productId = 9,
  double quantity = 2.0,
  String createdAt = '2026-07-24T10:00:00Z',
}) {
  return {
    'id': id,
    'productId': productId,
    'priceChipId': priceChipId,
    'blankId': blankId,
    'quantity': quantity,
    'createdAt': createdAt,
  };
}

Map<String, dynamic> _stockEntryJson({
  int id = 7,
  int blankId = 2,
  double quantity = 10.0,
  String type = 'production',
  String producedDate = '2026-07-24',
  String? expiryDate,
  String createdAt = '2026-07-24T10:00:00Z',
}) {
  return {
    'id': id,
    'blankId': blankId,
    'quantity': quantity,
    'producedDate': producedDate,
    'expiryDate': expiryDate,
    'type': type,
    'createdAt': createdAt,
  };
}

Map<String, dynamic> _stockSummaryJson({
  int blankId = 2,
  String name = 'Phôi cốt',
  String category = 'cot',
  String unit = 'cai',
  double stock = 12.0,
}) {
  return {
    'blankId': blankId,
    'name': name,
    'category': category,
    'unit': unit,
    'stock': stock,
  };
}

Map<String, dynamic> _demandJson({
  int blankId = 2,
  String name = 'Phôi cốt',
  String category = 'cot',
  String unit = 'cai',
  double demand = 20.0,
  double stock = 12.0,
  double shortage = 8.0,
}) {
  return {
    'blankId': blankId,
    'name': name,
    'category': category,
    'unit': unit,
    'demand': demand,
    'stock': stock,
    'shortage': shortage,
  };
}

Map<String, dynamic> _stockLogJson({
  int id = 1,
  int blankId = 2,
  double quantityChange = 10.0,
  String type = 'production',
  String? producedDate = '2026-07-24',
  String? expiryDate,
  String createdAt = '2026-07-24T10:00:00Z',
}) {
  return {
    'id': id,
    'blankId': blankId,
    'quantityChange': quantityChange,
    'type': type,
    'producedDate': producedDate,
    'expiryDate': expiryDate,
    'createdAt': createdAt,
  };
}

void main() {
  group('BlankService.blankCrud', () {
    test('listBlanks calls GET /api/blanks and parses response', () async {
      final interceptor = _RecordingInterceptor([_blankJson()]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final blanks = await service.listBlanks();

      expect(interceptor.method, 'GET');
      expect(interceptor.path, '/api/blanks');
      expect(blanks.length, 1);
      expect(blanks.first.id, 1);
      expect(blanks.first.name, 'Phôi cốt');
      expect(blanks.first.category, 'cot');
      expect(blanks.first.createdAt, '2026-07-24T10:00:00Z');
    });

    test('listBlanks forwards category query parameter', () async {
      final interceptor = _RecordingInterceptor(<Map<String, dynamic>>[]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      await service.listBlanks(category: 'kem');

      expect(interceptor.query, containsPair('category', 'kem'));
    });

    test('createBlank POSTs camelCase body and parses created blank', () async {
      final interceptor = _RecordingInterceptor(_blankJson(id: 3, name: 'Phôi kem'));
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final blank = await service.createBlank(name: 'Phôi kem', category: 'kem');

      expect(interceptor.method, 'POST');
      expect(interceptor.path, '/api/blanks');
      expect(interceptor.body, containsPair('name', 'Phôi kem'));
      expect(interceptor.body, containsPair('category', 'kem'));
      expect(blank.id, 3);
      expect(blank.name, 'Phôi kem');
    });

    test('updateBlank PATCHes only non-null fields', () async {
      final interceptor =
          _RecordingInterceptor(_blankJson(id: 1, notes: 'updated'));
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final blank = await service.updateBlank(1, notes: 'updated');

      expect(interceptor.method, 'PATCH');
      expect(interceptor.path, '/api/blanks/1');
      expect(interceptor.body, isNot(contains('name')));
      expect(interceptor.body, containsPair('notes', 'updated'));
      expect(blank.notes, 'updated');
    });

    test('deleteBlank issues DELETE and returns void', () async {
      final interceptor = _RecordingInterceptor(<String, dynamic>{});
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      await service.deleteBlank(4);

      expect(interceptor.method, 'DELETE');
      expect(interceptor.path, '/api/blanks/4');
    });
  });

  group('BlankService.bom', () {
    test('listBom calls GET /api/price-chips/{chipId}/blanks', () async {
      final interceptor = _RecordingInterceptor([_bomJson()]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final boms = await service.listBom(5);

      expect(interceptor.method, 'GET');
      expect(interceptor.path, '/api/price-chips/5/blanks');
      expect(boms.length, 1);
      expect(boms.first.priceChipId, 5);
      expect(boms.first.blankId, 2);
      expect(boms.first.quantity, 2.0);
    });

    test('createBom POSTs blankId and quantity', () async {
      final interceptor = _RecordingInterceptor(_bomJson(id: 10));
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final bom = await service.createBom(5, 2, 3.0);

      expect(interceptor.method, 'POST');
      expect(interceptor.path, '/api/price-chips/5/blanks');
      expect(interceptor.body, containsPair('blankId', 2));
      expect(interceptor.body, containsPair('quantity', 3.0));
      expect(bom.id, 10);
    });

    test('updateBom PATCHes quantity at bom path', () async {
      final interceptor = _RecordingInterceptor(_bomJson(quantity: 4.0));
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final bom = await service.updateBom(5, 10, 4.0);

      expect(interceptor.method, 'PATCH');
      expect(interceptor.path, '/api/price-chips/5/blanks/10');
      expect(interceptor.body, containsPair('quantity', 4.0));
      expect(bom.quantity, 4.0);
    });

    test('deleteBom issues DELETE at bom path', () async {
      final interceptor = _RecordingInterceptor(<String, dynamic>{});
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      await service.deleteBom(5, 10);

      expect(interceptor.method, 'DELETE');
      expect(interceptor.path, '/api/price-chips/5/blanks/10');
    });
  });

  group('BlankService.stock', () {
    test('getStock calls GET /api/blanks/stock and parses summaries', () async {
      final interceptor = _RecordingInterceptor([_stockSummaryJson()]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final summaries = await service.getStock();

      expect(interceptor.method, 'GET');
      expect(interceptor.path, '/api/blanks/stock');
      expect(summaries.length, 1);
      expect(summaries.first.blankId, 2);
      expect(summaries.first.stock, 12.0);
    });

    test('recordStock POSTs camelCase body and parses entry', () async {
      final interceptor = _RecordingInterceptor(_stockEntryJson());
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final entry = await service.recordStock(
        2,
        10.0,
        'production',
        producedDate: '2026-07-24',
        expiryDate: '2026-07-31',
      );

      expect(interceptor.method, 'POST');
      expect(interceptor.path, '/api/blanks/stock');
      expect(interceptor.body, containsPair('blankId', 2));
      expect(interceptor.body, containsPair('quantity', 10.0));
      expect(interceptor.body, containsPair('type', 'production'));
      expect(interceptor.body, containsPair('producedDate', '2026-07-24'));
      expect(interceptor.body, containsPair('expiryDate', '2026-07-31'));
      expect(entry.id, 7);
      expect(entry.blankId, 2);
      expect(entry.type, 'production');
    });
  });

  group('BlankService.demand', () {
    test('getDemand calls GET /api/blanks/demand and parses response', () async {
      final interceptor = _RecordingInterceptor([_demandJson()]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final demand = await service.getDemand();

      expect(interceptor.method, 'GET');
      expect(interceptor.path, '/api/blanks/demand');
      expect(demand.length, 1);
      expect(demand.first.blankId, 2);
      expect(demand.first.demand, 20.0);
      expect(demand.first.stock, 12.0);
      expect(demand.first.shortage, 8.0);
    });
  });

  group('BlankService.stockLog', () {
    test('listStockLog calls GET /api/blanks/{id}/stock-log and parses entries',
        () async {
      final interceptor = _RecordingInterceptor([_stockLogJson()]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final entries = await service.listStockLog(2);

      expect(interceptor.method, 'GET');
      expect(interceptor.path, '/api/blanks/2/stock-log');
      expect(entries.length, 1);
      expect(entries.first.id, 1);
      expect(entries.first.blankId, 2);
      expect(entries.first.quantityChange, 10.0);
      expect(entries.first.type, 'production');
      expect(entries.first.producedDate, '2026-07-24');
    });

    test('listStockLog parses usage entries with negative change', () async {
      final interceptor = _RecordingInterceptor([
        _stockLogJson(id: 2, quantityChange: -4.0, type: 'usage', producedDate: null),
      ]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = BlankService(dio);

      final entries = await service.listStockLog(2);

      expect(entries.first.quantityChange, -4.0);
      expect(entries.first.type, 'usage');
      expect(entries.first.producedDate, isNull);
    });
  });
}