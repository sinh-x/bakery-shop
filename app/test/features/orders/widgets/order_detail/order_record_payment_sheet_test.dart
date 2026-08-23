import 'dart:async';

import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:bakery_app/features/orders/providers/order_draft_contexts.dart';
import 'package:bakery_app/features/orders/providers/order_record_payment_notifier.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_record_payment_sheet.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox(height: 600, child: SingleChildScrollView(child: child)),
    ),
  ),
);

class _RecordPaymentService extends PaymentTransactionService {
  _RecordPaymentService() : super(Dio());

  int records = 0;

  @override
  Future<List<PaymentTransaction>> listTransactions(String orderRef) async =>
      [];

  @override
  Future<PaymentTransaction> createTransaction(
    String orderRef, {
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
    String? paymentSource,
    DateTime? createdAt,
  }) async => PaymentTransaction(
    id: 'txn-${++records}',
    orderId: 'order-1',
    amount: amount,
    type: type,
    method: method,
    notes: notes,
    paymentSource: paymentSource,
    createdAt: createdAt,
  );

  @override
  Future<PaymentTransactionPhoto> linkTransactionPhoto(
    String orderRef,
    String txnId,
    String photoHash,
  ) async => PaymentTransactionPhoto(
    id: 'link-$txnId',
    paymentTransactionId: txnId,
    photoId: '1',
    photoHash: photoHash,
    createdAt: '2026-08-24T00:00:00Z',
  );
}

class _DelayedPhotoOrderService extends OrderService {
  _DelayedPhotoOrderService() : super(Dio());

  final firstUpload = Completer<OrderPhoto>();
  final uploadedFiles = <XFile>[];

  @override
  Future<OrderPhoto> uploadOrderPhoto(
    String orderRef,
    XFile file, {
    String tags = '',
    int? workItemId,
  }) {
    uploadedFiles.add(file);
    if (uploadedFiles.length == 1) return firstUpload.future;
    return Future.value(_photo(uploadedFiles.length));
  }

  @override
  Future<Order> getOrder(String ref) async => Order(
    id: 'order-1',
    orderRef: ref,
    customerName: 'Test',
    items: const [],
    totalPrice: 100000,
    createdAt: DateTime(2026, 8, 24),
    updatedAt: DateTime(2026, 8, 24),
  );

  OrderPhoto _photo(int id) =>
      OrderPhoto(id: id, orderId: 1, photoHash: 'hash-$id');
}

void main() {
  group('OrderRecordPaymentSheet photo flow (FR2/FR3/FR4/AC2/AC3)', () {
    testWidgets(
      'delayed upload removes only its photo from a reopened edited draft',
      (tester) async {
        const orderRef = 'ORD-DELAYED-PHOTO';
        final paymentService = _RecordPaymentService();
        final orderService = _DelayedPhotoOrderService();
        final container = ProviderContainer(
          overrides: [
            paymentTransactionServiceProvider.overrideWithValue(paymentService),
            orderServiceProvider.overrideWithValue(orderService),
          ],
        );
        addTearDown(container.dispose);
        final draftContext = OrderDraftContexts.recordPayment(orderRef);
        final draftProvider = orderRecordPaymentDraftProvider(draftContext);
        final oldPhoto = XFile('/tmp/old-transfer.jpg');
        final newPhoto = XFile('/tmp/new-transfer.jpg');
        container.read(draftProvider.notifier)
          ..setAmount('100')
          ..setMethod('transfer')
          ..setPaymentSource(ExpensesLabels.paymentSourcePhuongVCB)
          ..setPendingTransferPhoto(oldPhoto);

        Widget app(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

        const sheet = OrderRecordPaymentSheet(
          orderRef: orderRef,
          remaining: 100000,
        );
        await tester.pumpWidget(app(sheet));
        await tester.pumpAndSettle();
        final submit = find.widgetWithText(
          FilledButton,
          OrdersLabels.addPayment,
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(orderService.uploadedFiles, [same(oldPhoto)]);

        await tester.pumpWidget(app(const SizedBox.shrink()));
        await tester.pumpWidget(app(sheet));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField).at(1), 'newer edit');
        await tester.pump();

        orderService.firstUpload.complete(orderService._photo(1));
        await tester.pumpAndSettle();

        final retained = container.read(draftProvider);
        expect(retained.notes, 'newer edit');
        expect(retained.pendingTransferPhoto, isNull);
        expect(
          container.read(formDraftSessionProvider),
          contains(draftContext),
        );

        container
            .read(draftProvider.notifier)
            .setPendingTransferPhoto(newPhoto);
        await tester.pump();
        expect(
          container.read(draftProvider).pendingTransferPhoto,
          same(newPhoto),
        );

        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(orderService.uploadedFiles, [same(oldPhoto), same(newPhoto)]);
        expect(
          orderService.uploadedFiles.where((file) => identical(file, oldPhoto)),
          hasLength(1),
        );
        expect(paymentService.records, 2);
      },
    );

    testWidgets(
      'cash method does not show the photo attachment button or target '
      'account dropdown (FR2)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const OrderRecordPaymentSheet(orderRef: 'ORD-1', remaining: 100000),
          ),
        );

        // Cash is the default method — no transfer-only UI.
        expect(find.byType(TargetAccountDropdown), findsNothing);
        expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
        expect(find.text(OrdersLabels.attachTransferPhoto), findsNothing);
      },
    );

    testWidgets('transfer method shows the target account dropdown and photo '
        'attachment button (FR2)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(orderRef: 'ORD-1', remaining: 100000),
          ),
        ),
      );

      // Switch to transfer method.
      await tester.tap(find.text(OrdersLabels.methodTransfer));
      await tester.pumpAndSettle();

      // Transfer-only UI is now visible.
      expect(find.byType(TargetAccountDropdown), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.text(OrdersLabels.attachTransferPhoto), findsOneWidget);
      expect(find.text(OrdersLabels.attachTransferPhotoTooltip), findsNothing);
    });

    testWidgets('photo attachment button has the expected tooltip (FR2/NFR4)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(orderRef: 'ORD-1', remaining: 100000),
          ),
        ),
      );

      await tester.tap(find.text(OrdersLabels.methodTransfer));
      await tester.pumpAndSettle();

      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, OrdersLabels.attachTransferPhotoTooltip);
    });

    testWidgets('switching back to cash hides the photo attachment button and '
        'clears the pending transfer photo (FR2)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(orderRef: 'ORD-1', remaining: 100000),
          ),
        ),
      );

      // Switch to transfer then back to cash.
      await tester.tap(find.text(OrdersLabels.methodTransfer));
      await tester.pumpAndSettle();
      expect(find.text(OrdersLabels.attachTransferPhoto), findsOneWidget);

      await tester.tap(find.text(OrdersLabels.methodCash));
      await tester.pumpAndSettle();

      // Transfer-only UI is hidden again.
      expect(find.byType(TargetAccountDropdown), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
      expect(find.text(OrdersLabels.attachTransferPhoto), findsNothing);
    });
  });

  group('sanitizeAccountTag (FR4/AC3)', () {
    test('spaces are replaced with hyphens', () {
      expect(sanitizeAccountTag('TK Phượng VCB'), 'TK-Phượng-VCB');
    });

    test('null or empty input returns empty string', () {
      expect(sanitizeAccountTag(null), '');
      expect(sanitizeAccountTag(''), '');
    });

    test('special characters are stripped (Unicode letters preserved)', () {
      // Parentheses and exclamation are stripped; Unicode letters/digits
      // and hyphens are preserved.
      expect(sanitizeAccountTag('TK (Phượng!) VCB'), 'TK-Phượng-VCB');
    });

    test('repeated hyphens are collapsed', () {
      expect(sanitizeAccountTag('A   B  C'), 'A-B-C');
    });

    test('leading and trailing hyphens are trimmed', () {
      expect(sanitizeAccountTag(' A B '), 'A-B');
    });

    test('tag string for "TK Phượng VCB" is "chuyen-khoan,TK-Phượng-VCB" '
        '(AC3)', () {
      final accountTag = sanitizeAccountTag(
        ExpensesLabels.paymentSourcePhuongVCB,
      );
      expect(accountTag, 'TK-Phượng-VCB');
      final tags = accountTag.isEmpty
          ? 'chuyen-khoan'
          : 'chuyen-khoan,$accountTag';
      expect(tags, 'chuyen-khoan,TK-Phượng-VCB');
    });

    test('empty account produces a bare "chuyen-khoan" tag', () {
      final accountTag = sanitizeAccountTag(null);
      final tags = accountTag.isEmpty
          ? 'chuyen-khoan'
          : 'chuyen-khoan,$accountTag';
      expect(tags, 'chuyen-khoan');
    });
  });
}
