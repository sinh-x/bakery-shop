import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingInterceptor extends Interceptor {
  String? lastPath;
  Map<String, dynamic>? lastBody;
  Map<String, dynamic> responseJson;

  _RecordingInterceptor(this.responseJson);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastBody = options.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(options.data as Map)
        : null;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: responseJson,
      ),
    );
  }
}

Map<String, dynamic> _txnJson({
  String invalidatedAt = '',
  String invalidatedBy = '',
}) {
  return {
    'id': '20',
    'orderId': '1',
    'type': 'deposit',
    'method': 'cash',
    'amount': 200000.0,
    'note': '',
    'createdAt': '2026-06-25T10:00:00Z',
    if (invalidatedAt.isNotEmpty) 'invalidatedAt': invalidatedAt,
    'invalidatedBy': invalidatedBy,
  };
}

void main() {
  group('PaymentTransactionService invalidate/restore', () {
    test('invalidateTransaction POSTs to invalidate endpoint with body', () async {
      final interceptor = _RecordingInterceptor(
        _txnJson(invalidatedAt: '2026-06-25T12:00:00Z', invalidatedBy: 'Sinh'),
      );
      final dio = Dio()..interceptors.add(interceptor);
      final service = PaymentTransactionService(dio);

      final txn = await service.invalidateTransaction(
        'ORD-260625-001',
        '20',
        invalidatedBy: 'Sinh',
        reason: 'sai so tien',
      );

      expect(interceptor.lastPath, '/api/orders/ORD-260625-001/transactions/20/invalidate');
      expect(interceptor.lastBody, containsPair('invalidatedBy', 'Sinh'));
      expect(interceptor.lastBody, containsPair('reason', 'sai so tien'));
      expect(txn.invalidatedAt, DateTime.parse('2026-06-25T12:00:00Z'));
      expect(txn.invalidatedBy, 'Sinh');
    });

    test('restoreTransaction POSTs to restore endpoint', () async {
      final interceptor = _RecordingInterceptor(_txnJson());
      final dio = Dio()..interceptors.add(interceptor);
      final service = PaymentTransactionService(dio);

      await service.restoreTransaction('ORD-260625-001', '20');

      expect(interceptor.lastPath, '/api/orders/ORD-260625-001/transactions/20/restore');
      expect(interceptor.lastBody, isNull);
    });
  });

  group('PaymentTransactionService listTransactions parses invalidated fields', () {
    test('invalidated transactions surface invalidatedAt/invalidatedBy', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _txnJson(invalidatedAt: '2026-06-25T12:00:00Z', invalidatedBy: 'An'),
                    _txnJson(),
                  ],
                ),
              );
            },
          ),
        );
      final service = PaymentTransactionService(dio);

      final txns = await service.listTransactions('ORD-260625-001');

      expect(txns.length, 2);
      expect(txns[0].invalidatedAt, DateTime.parse('2026-06-25T12:00:00Z'));
      expect(txns[0].invalidatedBy, 'An');
      expect(txns[1].invalidatedAt, isNull);
      expect(txns[1].invalidatedBy, '');
    });
  });
}