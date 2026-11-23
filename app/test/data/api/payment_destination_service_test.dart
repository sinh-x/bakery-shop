import 'package:bakery_app/data/api/payment_destination_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lists unresolved receipts with pagination, search and neutral metadata',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path, '/api/payment-destinations');
              expect(options.queryParameters, {
                'search': 'ORD',
                'offset': 50,
                'limit': 50,
              });
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'items': [
                      {
                        'id': '1',
                        'orderId': '2',
                        'orderRef': 'ORD',
                        'customerName': 'Khách',
                        'method': 'unknown',
                        'amount': 100000,
                        'destinationStatus': 'unresolved',
                      },
                    ],
                    'total': 51,
                    'unresolvedAmount': 5100000,
                    'has_more': false,
                  },
                ),
              );
            },
          ),
        );
      final page = await PaymentDestinationService(
        dio,
      ).list(search: 'ORD', offset: 50);
      expect(page.total, 51);
      expect(page.amount, 5100000);
      expect(page.hasMore, false);
      expect(page.items.single.transaction.hasUnknownOrigin, true);
      expect(page.items.single.orderRef, 'ORD');
    },
  );

  test(
    'assignment posts destination only and parses resolution metadata',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(
                options.path,
                '/api/orders/ORD/transactions/1/destination',
              );
              expect(options.data, {
                'method': 'transfer',
                'payment_source': 'TK Ân VCB',
              });
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'id': '1',
                    'orderId': '2',
                    'method': 'transfer',
                    'amount': 100000,
                    'destinationStatus': 'resolved',
                    'destinationResolvedAt': '2026-11-22T18:00:00Z',
                    'destinationResolvedBy': 'staff',
                  },
                ),
              );
            },
          ),
        );
      final txn = await PaymentDestinationService(
        dio,
      ).assign('ORD', '1', method: 'transfer', paymentSource: 'TK Ân VCB');
      expect(txn.hasUnknownOrigin, true);
      expect(txn.destinationStatus, 'resolved');
      expect(txn.destinationResolvedBy, 'staff');
      expect(txn.destinationResolvedAt, DateTime.utc(2026, 11, 22, 18));
    },
  );

  test('legacy transactions retain known-destination defaults', () {
    final txn = PaymentTransaction.fromJson({
      'id': '1',
      'orderId': '2',
      'amount': 100,
    });
    expect(txn.destinationStatus, 'known');
    expect(txn.hasUnknownOrigin, false);
  });
}
