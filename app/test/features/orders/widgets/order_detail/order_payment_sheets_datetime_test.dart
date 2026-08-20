import 'package:bakery_app/data/api/api_client.dart'
    show ApiBaseUrlNotifier, apiBaseUrlProvider;
import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/payment_transaction_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_edit_payment_sheet.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_record_payment_sheet.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/expenses.dart';

const _testRef = 'TEST-ORD-DATETIME';
const _testBaseUrl = 'http://test.local:8000';

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => _testBaseUrl;
}

/// Fake service whose `getTransactionPhoto` returns null so the edit sheet's
/// photo section renders the empty (attach) state without network calls.
class _FakeTxnPhotoService extends PaymentTransactionService {
  _FakeTxnPhotoService() : super(Dio());

  @override
  Future<PaymentTransactionPhoto?> getTransactionPhoto(
    String orderRef,
    String txnId,
  ) async {
    await Future<void>.delayed(Duration.zero);
    return null;
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
            height: 800,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

PaymentTransaction _txn({DateTime? createdAt}) => PaymentTransaction(
      id: 'txn-1',
      orderId: 'ord-1',
      type: 'payment',
      method: 'transfer',
      amount: 200000,
      notes: '',
      paymentSource: ExpensesLabels.paymentSourcePhuongVCB,
      createdAt: createdAt,
    );

void main() {
  group('OrderRecordPaymentSheet date+time picker (DG-415 Phase 3 / FR1, FR7)',
      () {
    testWidgets(
        'shows the picker row with date and time labels defaulting to now '
        '(AC1)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OrderRecordPaymentSheet(
            orderRef: _testRef,
            remaining: 100000,
          ),
          _FakeTxnPhotoService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.txnDateLabel), findsOneWidget);
      expect(find.text(OrdersLabels.txnTimeLabel), findsOneWidget);
      // Two picker icons — date + time.
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });
  });

  group('OrderEditPaymentSheet date+time picker (DG-415 Phase 3 / FR2, AC3)',
      () {
    testWidgets(
        'pre-fills the picker with the existing transaction createdAt '
        '(AC3)', (tester) async {
      final existing = DateTime.parse('2026-08-16T06:00:00Z');
      await tester.pumpWidget(
        _wrap(
          OrderEditPaymentSheet(
            orderRef: _testRef,
            txn: _txn(createdAt: existing),
          ),
          _FakeTxnPhotoService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.txnDateLabel), findsOneWidget);
      expect(find.text(OrdersLabels.txnTimeLabel), findsOneWidget);
      // The picker renders the local wall-clock representation of the UTC
      // instant. The label is built from the device-local fields of the
      // DateTime; DateTime.parse('2026-08-16T06:00:00Z') is UTC and the
      // picker formats via TimeOfDay.fromDateTime + day/month/year which
      // use the raw fields, so we expect the UTC day/month/year here.
      expect(find.text('16/08/2026'), findsOneWidget);
    });
  });
}