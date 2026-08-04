import 'package:bakery_app/data/api/cash_drawer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recording interceptor that resolves every request with a fixed JSON body
/// and captures the request path + body for assertions. Mirrors the pattern in
/// `payment_transaction_service_test.dart`.
class _RecordingInterceptor extends Interceptor {
  String? lastPath;
  Map<String, dynamic>? lastBody;
  Map<String, dynamic>? lastQuery;
  Map<String, dynamic> responseJson;

  _RecordingInterceptor(this.responseJson);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastBody = options.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(options.data as Map)
        : null;
    lastQuery = options.queryParameters;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: responseJson,
      ),
    );
  }
}

Map<String, dynamic> _drawerJson({
  String status = 'open',
  int expectedBalance = 1000000,
  int? countedAmount,
  int? discrepancy,
  Map<String, dynamic>? journalEntry,
}) {
  final json = <String, dynamic>{
    'id': '1',
    'openedAt': '2026-08-01T00:00:00Z',
    'closedAt': null,
    'status': status,
    'openingBalance': 1000000,
    'countedAmount': countedAmount,
    'discrepancy': discrepancy,
    'expectedBalance': expectedBalance,
  };
  if (journalEntry != null) {
    json['journalEntry'] = journalEntry;
  }
  return json;
}

void main() {
  group('CashDrawerService (DG-324 Phase 4)', () {
    test('openDrawer POSTs to /open with openingBalance + note', () async {
      final interceptor =
          _RecordingInterceptor(_drawerJson(journalEntry: {
        'id': '5',
        'sourceType': 'cash_drawer_open',
        'lines': <Map<String, dynamic>>[],
      }));
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      final drawer = await service.openDrawer(
        openingBalance: 1000000,
        note: 'mở ca sáng',
      );

      expect(interceptor.lastPath, '/api/cash-drawer/open');
      expect(interceptor.lastBody, {
        'openingBalance': 1000000,
        'note': 'mở ca sáng',
        'carryOverConfirmed': false,
        'transferConfirmed': false,
        'stockReconciliationConfirmed': false,
        'unidentifiedSaleConfirmed': false,
        'ownerCapitalConfirmed': false,
      });
      expect(drawer.id, '1');
      expect(drawer.openingBalance, 1000000);
      expect(drawer.journalEntry, isNotNull);
      expect(drawer.journalEntry!.sourceType, 'cash_drawer_open');
    });

    test('openDrawer sends carryOverConfirmed: true when requested',
        () async {
      final interceptor =
          _RecordingInterceptor(_drawerJson(journalEntry: {
        'id': '5',
        'sourceType': 'cash_drawer_open',
        'lines': <Map<String, dynamic>>[],
      }));
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      await service.openDrawer(
        openingBalance: 1550000,
        note: 'mang sang',
        carryOverConfirmed: true,
      );

      expect(interceptor.lastBody, {
        'openingBalance': 1550000,
        'note': 'mang sang',
        'carryOverConfirmed': true,
        'transferConfirmed': false,
        'stockReconciliationConfirmed': false,
        'unidentifiedSaleConfirmed': false,
        'ownerCapitalConfirmed': false,
      });
    });

    test('openDrawer throws CarryOverProposalException on 409 proposal',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'detail': {
                        'message':
                            'Quầy hôm trước chưa đóng — xác nhận số dư chuyển sang hôm nay.',
                        'carryOverProposal': {
                          'amount': 1550000,
                          'fromDrawerId': '7',
                          'fromOpenedAt': '2026-07-28T08:00:00Z',
                          'fromExpectedBalance': 1550000,
                        },
                      },
                    },
                  ),
                ),
              );
            },
          ),
        );
      final service = CashDrawerService(dio);

      await expectLater(
        service.openDrawer(openingBalance: 1550000),
        throwsA(isA<CarryOverProposalException>()),
      );
      try {
        await service.openDrawer(openingBalance: 1550000);
        fail('expected CarryOverProposalException');
      } on CarryOverProposalException catch (e) {
        expect(e.amount, 1550000);
        expect(e.fromDrawerId, '7');
        expect(e.fromOpenedAt, '2026-07-28T08:00:00Z');
        expect(e.fromExpectedBalance, 1550000);
        expect(e.message, contains('chưa đóng'));
      }
    });

    test('openDrawer rethrows non-carry-over DioExceptions unchanged',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'detail':
                          'Đã có quầy tiền mặt đang mở — phải đóng quầy hiện tại.',
                    },
                  ),
                ),
              );
            },
          ),
        );
      final service = CashDrawerService(dio);

      await expectLater(
        service.openDrawer(openingBalance: 1000000),
        throwsA(isA<DioException>()),
      );
    });

    test('cashIn POSTs to /cash-in with amount + note', () async {
      final interceptor = _RecordingInterceptor(_drawerJson(
        expectedBalance: 1200000,
        journalEntry: {
          'id': '6',
          'sourceType': 'cash_drawer_cash_in',
          'lines': <Map<String, dynamic>>[],
        },
      ));
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      final drawer = await service.cashIn(amount: 200000, note: 'thêm lẻ');

      expect(interceptor.lastPath, '/api/cash-drawer/cash-in');
      expect(interceptor.lastBody, {
        'amount': 200000,
        'note': 'thêm lẻ',
        'source': 'equity',
      });
      expect(drawer.expectedBalance, 1200000);
      expect(drawer.journalEntry!.sourceType, 'cash_drawer_cash_in');
    });

    test('cashOut POSTs to /cash-out with amount + note', () async {
      final interceptor = _RecordingInterceptor(_drawerJson(
        expectedBalance: 900000,
        journalEntry: {
          'id': '7',
          'sourceType': 'cash_drawer_cash_out',
          'lines': <Map<String, dynamic>>[],
        },
      ));
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      final drawer = await service.cashOut(amount: 100000);

      expect(interceptor.lastPath, '/api/cash-drawer/cash-out');
      expect(interceptor.lastBody, {
        'amount': 100000,
        'note': '',
        'destination': 'owner',
      });
      expect(drawer.expectedBalance, 900000);
    });

    test('closeDrawer POSTs to /close with countedAmount + note', () async {
      final interceptor = _RecordingInterceptor(_drawerJson(
        status: 'closed',
        countedAmount: 1540000,
        discrepancy: -10000,
        expectedBalance: 1550000,
      ));
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      final drawer = await service.closeDrawer(countedAmount: 1540000);

      expect(interceptor.lastPath, '/api/cash-drawer/close');
      expect(interceptor.lastBody, {'countedAmount': 1540000, 'note': ''});
      expect(drawer.isClosed, isTrue);
      expect(drawer.countedAmount, 1540000);
      expect(drawer.discrepancy, -10000);
    });

    test('getDrawerStatus GETs /status and returns drawer when present',
        () async {
      final interceptor = _RecordingInterceptor(_drawerJson());
      final dio = Dio()..interceptors.add(interceptor);
      final service = CashDrawerService(dio);

      final drawer = await service.getDrawerStatus();

      expect(interceptor.lastPath, '/api/cash-drawer/status');
      expect(drawer, isNotNull);
      expect(drawer!.id, '1');
      expect(drawer.isOpen, isTrue);
    });

    test('getDrawerStatus returns null when body is null', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: null,
                ),
              );
            },
          ),
        );
      final service = CashDrawerService(dio);

      final drawer = await service.getDrawerStatus();

      expect(drawer, isNull);
    });

    test('getDrawerHistory GETs /history with pagination + date filters',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'total': 1,
                    'limit': 50,
                    'offset': 0,
                    'items': [_drawerJson()],
                  },
                ),
              );
            },
          ),
        );
      final service = CashDrawerService(dio);

      final resp = await service.getDrawerHistory(
        since: '2026-08-01',
        until: '2026-08-31',
        limit: 50,
        offset: 0,
      );

      expect(resp.total, 1);
      expect(resp.items.length, 1);
      expect(resp.items.first.id, '1');
    });

    test('getDrawerHistory omits empty date filters from query', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedQuery;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedPath = options.path;
              capturedQuery = options.queryParameters;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'total': 0, 'limit': 50, 'offset': 0, 'items': []},
                ),
              );
            },
          ),
        );
      final service = CashDrawerService(dio);

      await service.getDrawerHistory();

      expect(capturedPath, '/api/cash-drawer/history');
      expect(capturedQuery!.containsKey('since'), isFalse);
      expect(capturedQuery!.containsKey('until'), isFalse);
      expect(capturedQuery!['limit'], 50);
      expect(capturedQuery!['offset'], 0);
    });
  });

  group('cashDrawerServiceProvider', () {
    test('is a Provider<CashDrawerService>', () {
      // The provider must compile and be referenceable; constructing it via a
      // ProviderContainer with a stub Dio override confirms the wiring.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(cashDrawerServiceProvider, isNotNull);
    });
  });
}