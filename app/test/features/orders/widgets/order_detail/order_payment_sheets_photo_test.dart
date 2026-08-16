import 'package:bakery_app/data/api/api_client.dart'
    show ApiBaseUrlNotifier, apiBaseUrlProvider;
import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_edit_payment_sheet.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_transaction_detail_sheet.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

const _testRef = 'TEST-ORD-PHOTO-UI';
const _testBaseUrl = 'http://test.local:8000';

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => _testBaseUrl;
}

PaymentTransaction _txn() => const PaymentTransaction(
      id: 'txn-1',
      orderId: 'ord-1',
      type: 'payment',
      method: 'transfer',
      amount: 200000,
      notes: '',
      paymentSource: VN.paymentSourcePhuongVCB,
    );

/// Fake service that controls what [getTransactionPhoto] returns so the
/// edit / detail sheets can render the "has photo" vs "no photo" branch.
class _FakeTxnPhotoService extends PaymentTransactionService {
  _FakeTxnPhotoService({this.photo}) : super(Dio());

  final PaymentTransactionPhoto? photo;
  String? lastAttachTxnId;
  String? lastDetachTxnId;

  @override
  Future<PaymentTransactionPhoto?> getTransactionPhoto(
    String orderRef,
    String txnId,
  ) async {
    await Future<void>.delayed(Duration.zero);
    return photo;
  }

  @override
  Future<PaymentTransactionPhoto> attachTransactionPhoto(
    String orderRef,
    String txnId,
    XFile file,
  ) async {
    await Future<void>.delayed(Duration.zero);
    lastAttachTxnId = txnId;
    return const PaymentTransactionPhoto(
      id: 'link-1',
      paymentTransactionId: 'txn-1',
      photoId: '9',
      photoHash: 'attached-hash',
      createdAt: '2026-08-16T06:00:00Z',
    );
  }

  @override
  Future<void> detachTransactionPhoto(String orderRef, String txnId) async {
    lastDetachTxnId = txnId;
  }
}

Widget _wrap(Widget child, PaymentTransactionService service) => ProviderScope(
      overrides: [
        apiBaseUrlProvider.overrideWith(_FakeApiBaseUrlNotifier.new),
        paymentTransactionServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  group('OrderEditPaymentSheet photo section (FR3 / AC2)', () {
    testWidgets(
        'no attached photo shows the attach button (AC2 add)', (tester) async {
      final service = _FakeTxnPhotoService(photo: null);
      await tester.pumpWidget(
        _wrap(
          OrderEditPaymentSheet(orderRef: _testRef, txn: _txn()),
          service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.txnPhotoSection), findsOneWidget);
      expect(find.text(VN.txnPhotoAttach), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      // Replace / Remove are not shown when there is no photo.
      expect(find.text(VN.txnPhotoReplace), findsNothing);
      expect(find.text(VN.txnPhotoRemove), findsNothing);
    });

    testWidgets(
        'attached photo shows the thumbnail, Replace and Remove buttons (AC2)',
        (tester) async {
      final service = _FakeTxnPhotoService(
        photo: const PaymentTransactionPhoto(
          id: 'link-1',
          paymentTransactionId: 'txn-1',
          photoId: '7',
          photoHash: 'abc123',
          createdAt: '2026-08-16T06:00:00Z',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          OrderEditPaymentSheet(orderRef: _testRef, txn: _txn()),
          service,
        ),
      );
      await tester.pumpAndSettle();

      // The attach button is replaced by Replace + Remove.
      expect(find.text(VN.txnPhotoAttach), findsNothing);
      expect(find.text(VN.txnPhotoReplace), findsOneWidget);
      expect(find.text(VN.txnPhotoRemove), findsOneWidget);
      // The thumbnail renders an Image.network pointing at the photo URL.
      final image = find.byType(Image);
      expect(image, findsWidgets);
    });

    testWidgets('Remove opens a confirm dialog (AC2 remove)', (tester) async {
      final service = _FakeTxnPhotoService(
        photo: const PaymentTransactionPhoto(
          id: 'link-1',
          paymentTransactionId: 'txn-1',
          photoId: '7',
          photoHash: 'abc123',
          createdAt: '2026-08-16T06:00:00Z',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          OrderEditPaymentSheet(orderRef: _testRef, txn: _txn()),
          service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(VN.txnPhotoRemove));
      await tester.pumpAndSettle();

      // Confirm dialog appears with the remove + cancel actions.
      expect(find.text(VN.txnPhotoRemove), findsOneWidget);
      expect(find.text(VN.cancel), findsOneWidget);
      expect(find.text(VN.remove), findsOneWidget);
    });
  });

  group('OrderTransactionDetailSheet photo section (FR4 / AC3)', () {
    testWidgets(
        'no attached photo shows the empty state and inline attach button '
        '(AC3)', (tester) async {
      final service = _FakeTxnPhotoService(photo: null);
      await tester.pumpWidget(
        _wrap(
          OrderTransactionDetailSheet(
            txn: _txn(),
            orderRef: _testRef,
            onEdit: () {},
          ),
          service,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.txnPhotoSection), findsOneWidget);
      expect(find.text(VN.txnPhotoEmpty), findsOneWidget);
      expect(find.text(VN.txnPhotoAttach), findsOneWidget);
      // No Replace when there is no photo.
      expect(find.text(VN.txnPhotoReplace), findsNothing);
    });

    testWidgets(
        'attached photo shows the thumbnail and inline Replace button (AC3)',
        (tester) async {
      final service = _FakeTxnPhotoService(
        photo: const PaymentTransactionPhoto(
          id: 'link-1',
          paymentTransactionId: 'txn-1',
          photoId: '7',
          photoHash: 'abc123',
          createdAt: '2026-08-16T06:00:00Z',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          OrderTransactionDetailSheet(
            txn: _txn(),
            orderRef: _testRef,
            onEdit: () {},
          ),
          service,
        ),
      );
      await tester.pumpAndSettle();

      // Empty state is gone; Replace is shown inline.
      expect(find.text(VN.txnPhotoEmpty), findsNothing);
      expect(find.text(VN.txnPhotoAttach), findsNothing);
      expect(find.text(VN.txnPhotoReplace), findsOneWidget);
      // Thumbnail image present.
      expect(find.byType(Image), findsWidgets);
    });
  });
}