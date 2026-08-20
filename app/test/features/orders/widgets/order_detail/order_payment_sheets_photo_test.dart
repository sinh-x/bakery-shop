import 'package:bakery_app/data/api/api_client.dart'
    show ApiBaseUrlNotifier, apiBaseUrlProvider;
import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_edit_payment_sheet.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_transaction_detail_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

const _testRef = 'TEST-ORD-PHOTO-UI';
const _testBaseUrl = 'http://test.local:8000';

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => _testBaseUrl;
}

PaymentTransaction _txn({DateTime? invalidatedAt}) => PaymentTransaction(
      id: 'txn-1',
      orderId: 'ord-1',
      type: 'payment',
      method: 'transfer',
      amount: 200000,
      notes: '',
      paymentSource: ExpensesLabels.paymentSourcePhuongVCB,
      invalidatedAt: invalidatedAt,
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

      expect(find.text(OrdersLabels.txnPhotoSection), findsOneWidget);
      expect(find.text(OrdersLabels.txnPhotoAttach), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      // Replace / Remove are not shown when there is no photo.
      expect(find.text(OrdersLabels.txnPhotoReplace), findsNothing);
      expect(find.text(OrdersLabels.txnPhotoRemove), findsNothing);
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
      expect(find.text(OrdersLabels.txnPhotoAttach), findsNothing);
      expect(find.text(OrdersLabels.txnPhotoReplace), findsOneWidget);
      expect(find.text(OrdersLabels.txnPhotoRemove), findsOneWidget);
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

      // The Remove button may be offscreen because the sheet now also hosts
      // the date+time picker row (DG-415 Phase 3). Scroll it into view.
      final removeFinder = find.text(OrdersLabels.txnPhotoRemove);
      await tester.ensureVisible(removeFinder);
      await tester.pumpAndSettle();
      await tester.tap(removeFinder);
      await tester.pumpAndSettle();

      // Confirm dialog appears with the remove + cancel actions.
      expect(find.text(OrdersLabels.txnPhotoRemove), findsOneWidget);
      expect(find.text(SharedLabels.cancel), findsOneWidget);
      expect(find.text(SharedLabels.remove), findsOneWidget);
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

      expect(find.text(OrdersLabels.txnPhotoSection), findsOneWidget);
      expect(find.text(OrdersLabels.txnPhotoEmpty), findsOneWidget);
      expect(find.text(OrdersLabels.txnPhotoAttach), findsOneWidget);
      // No Replace when there is no photo.
      expect(find.text(OrdersLabels.txnPhotoReplace), findsNothing);
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
      expect(find.text(OrdersLabels.txnPhotoEmpty), findsNothing);
      expect(find.text(OrdersLabels.txnPhotoAttach), findsNothing);
      expect(find.text(OrdersLabels.txnPhotoReplace), findsOneWidget);
      // Thumbnail image present.
      expect(find.byType(Image), findsWidgets);
    });
  });

  // cycle-1 CQ-3: lock the invalidated-edit UI guard with a widget test so a
  // future refactor cannot re-introduce the Edit button for invalidated
  // transactions without a failing test.
  group('OrderTransactionDetailSheet invalidated guard (CQ-3)', () {
    testWidgets(
        'invalidated transaction hides Edit and shows Restore (CQ-3)',
        (tester) async {
      final service = _FakeTxnPhotoService(photo: null);
      await tester.pumpWidget(
        _wrap(
          OrderTransactionDetailSheet(
            txn: _txn(invalidatedAt: DateTime(2026, 8, 20, 10, 0, 0)),
            orderRef: _testRef,
            onEdit: () {},
          ),
          service,
        ),
      );
      await tester.pumpAndSettle();

      // Edit is hidden for invalidated transactions.
      expect(find.text(OrdersLabels.editPayment), findsNothing);
      // Restore is offered instead.
      expect(find.text(OrdersLabels.restorePayment), findsOneWidget);
      // The invalidate action must not also be surfaced when invalidated.
      expect(find.text(OrdersLabels.invalidatePayment), findsNothing);
    });

    testWidgets(
        'non-invalidated transaction shows Edit and Invalidate (CQ-3)',
        (tester) async {
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

      // Edit is shown for active (non-invalidated) transactions.
      expect(find.text(OrdersLabels.editPayment), findsOneWidget);
      // Invalidate (not Restore) is offered.
      expect(find.text(OrdersLabels.invalidatePayment), findsOneWidget);
      expect(find.text(OrdersLabels.restorePayment), findsNothing);
    });
  });
}