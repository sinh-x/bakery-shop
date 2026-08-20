import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _photoJson() {
  return {
    'id': '77',
    'paymentTransactionId': '20',
    'photoId': '7',
    'photoHash': 'abc123',
    'createdAt': '2026-08-16T05:49:42Z',
  };
}

void main() {
  group('PaymentTransactionService photo methods', () {
    test('getTransactionPhoto GETs the photo endpoint and parses payload',
        () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path,
                  '/api/orders/ORD-001/transactions/20/photo');
              expect(options.method, 'GET');
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _photoJson(),
                ),
              );
            },
          ),
        );
      final service = PaymentTransactionService(dio);

      final photo = await service.getTransactionPhoto('ORD-001', '20');

      expect(photo, isNotNull);
      expect(photo!.id, '77');
      expect(photo.paymentTransactionId, '20');
      expect(photo.photoHash, 'abc123');
    });

    test('linkTransactionPhoto POSTs photoHash to the link endpoint', () async {
      String? capturedPath;
      String? capturedMethod;
      Map<String, dynamic>? capturedBody;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedPath = options.path;
              capturedMethod = options.method;
              capturedBody = options.data is Map<String, dynamic>
                  ? Map<String, dynamic>.from(options.data as Map)
                  : null;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: _photoJson(),
                ),
              );
            },
          ),
        );
      final service = PaymentTransactionService(dio);

      final link = await service.linkTransactionPhoto('ORD-001', '20', 'abc123');

      expect(capturedPath, '/api/orders/ORD-001/transactions/20/photo/link');
      expect(capturedMethod, 'POST');
      expect(capturedBody, containsPair('photoHash', 'abc123'));
      expect(link.photoHash, 'abc123');
    });

    test('detachTransactionPhoto DELETEs the photo endpoint', () async {
      String? capturedPath;
      String? capturedMethod;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedPath = options.path;
              capturedMethod = options.method;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'message': 'Đã gỡ ảnh khỏi giao dịch'},
                ),
              );
            },
          ),
        );
      final service = PaymentTransactionService(dio);

      await service.detachTransactionPhoto('ORD-001', '20');

      expect(capturedPath, '/api/orders/ORD-001/transactions/20/photo');
      expect(capturedMethod, 'DELETE');
    });
  });
}