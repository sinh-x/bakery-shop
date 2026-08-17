import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:bakery_app/data/providers/order/order_payment_transaction_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

const _testRef = 'TEST-ORDER-PAY-PHOTO';

class _RecordingTxnPhotoService extends PaymentTransactionService {
  _RecordingTxnPhotoService() : super(Dio());

  String? lastLinkTxnId;
  String? lastLinkPhotoHash;
  String? lastDetachTxnId;
  String? lastGetTxnId;
  String? lastAttachTxnId;
  XFile? lastAttachFile;
  Object? getException;

  @override
  Future<PaymentTransactionPhoto> linkTransactionPhoto(
    String orderRef,
    String txnId,
    String photoHash,
  ) async {
    lastLinkTxnId = txnId;
    lastLinkPhotoHash = photoHash;
    return PaymentTransactionPhoto(
      id: 'link-1',
      paymentTransactionId: txnId,
      photoId: '7',
      photoHash: photoHash,
      createdAt: '2026-08-16T05:49:42Z',
    );
  }

  @override
  Future<PaymentTransactionPhoto> attachTransactionPhoto(
    String orderRef,
    String txnId,
    XFile file,
  ) async {
    lastAttachTxnId = txnId;
    lastAttachFile = file;
    return PaymentTransactionPhoto(
      id: 'link-2',
      paymentTransactionId: txnId,
      photoId: '8',
      photoHash: 'attached-hash',
      createdAt: '2026-08-16T05:49:42Z',
    );
  }

  @override
  Future<void> detachTransactionPhoto(String orderRef, String txnId) async {
    lastDetachTxnId = txnId;
  }

  @override
  Future<PaymentTransactionPhoto?> getTransactionPhoto(
    String orderRef,
    String txnId,
  ) async {
    lastGetTxnId = txnId;
    // Yield so the throw lands in the Future rather than synchronously.
    await Future<void>.delayed(Duration.zero);
    if (getException != null) {
      throw getException!;
    }
    return PaymentTransactionPhoto(
      id: 'link-1',
      paymentTransactionId: txnId,
      photoId: '7',
      photoHash: 'abc123',
      createdAt: '2026-08-16T05:49:42Z',
    );
  }
}

ProviderContainer _containerWithService(
  _RecordingTxnPhotoService service, {
  bool disableRetry = false,
}) {
  final container = ProviderContainer(
    overrides: [
      paymentTransactionServiceProvider.overrideWithValue(service),
    ],
    retry: disableRetry ? (_, _) => null : null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('OrderPaymentTransactionsNotifier photo methods', () {
    test('linkPhoto forwards txnId + photoHash to the service', () async {
      final service = _RecordingTxnPhotoService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      final link = await notifier.linkPhoto('txn-42', 'deadbeef');

      expect(service.lastLinkTxnId, 'txn-42');
      expect(service.lastLinkPhotoHash, 'deadbeef');
      expect(link.photoHash, 'deadbeef');
    });

    test('detachPhoto forwards txnId to the service', () async {
      final service = _RecordingTxnPhotoService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      await notifier.detachPhoto('txn-43');

      expect(service.lastDetachTxnId, 'txn-43');
    });

    test('attachPhoto forwards txnId + file to the service', () async {
      final service = _RecordingTxnPhotoService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      final file = XFile('test.png');
      final link = await notifier.attachPhoto('txn-44', file);

      expect(service.lastAttachTxnId, 'txn-44');
      expect(service.lastAttachFile, same(file));
      expect(link.photoHash, 'attached-hash');
    });
  });

  group('transactionPhotoProvider', () {
    test('returns the photo link from the service', () async {
      final service = _RecordingTxnPhotoService();
      final container = _containerWithService(service);

      final photo = await container.read(
        transactionPhotoProvider((_testRef, 'txn-50')).future,
      );

      expect(service.lastGetTxnId, 'txn-50');
      expect(photo, isNotNull);
      expect(photo!.photoHash, 'abc123');
    });

    test('normalizes a 404 DioException to null (NFR3 lazy fetch)', () async {
      final service = _RecordingTxnPhotoService();
      service.getException = DioException(
        requestOptions: RequestOptions(path: '/api/orders/x/transactions/1/photo'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/api/orders/x/transactions/1/photo'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
      final container = _containerWithService(service, disableRetry: true);

      final photo = await container.read(
        transactionPhotoProvider((_testRef, 'txn-51')).future,
      );

      expect(photo, isNull);
    });

    test('rethrows non-404 DioException', () async {
      final service = _RecordingTxnPhotoService();
      service.getException = DioException(
        requestOptions: RequestOptions(path: '/api/orders/x/transactions/1/photo'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/api/orders/x/transactions/1/photo'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final container = _containerWithService(service, disableRetry: true);

      // Watch the provider so it starts building; wait for the error to
      // surface in the state rather than awaiting `.future` (which races
      // with container disposal during teardown).
      container.read(transactionPhotoProvider((_testRef, 'txn-52')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(
        transactionPhotoProvider((_testRef, 'txn-52')),
      );
      expect(state, isA<AsyncError<PaymentTransactionPhoto?>>());
      expect(
        (state as AsyncError<PaymentTransactionPhoto?>).error,
        isA<DioException>(),
      );
    });
  });
}