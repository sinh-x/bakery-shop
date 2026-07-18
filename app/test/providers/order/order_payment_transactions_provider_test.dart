import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _testRef = 'TEST-ORDER-PAY-SRC';

class _RecordingTxnService extends PaymentTransactionService {
  _RecordingTxnService() : super(Dio());

  String? lastCreatePaymentSource;
  String? lastUpdatePaymentSource;
  String lastCreateOrderRef = '';
  String lastUpdateOrderRef = '';
  String lastUpdateTxnId = '';

  @override
  Future<PaymentTransaction> createTransaction(
    String orderRef, {
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
    String? paymentSource,
  }) async {
    lastCreateOrderRef = orderRef;
    lastCreatePaymentSource = paymentSource;
    return PaymentTransaction(
      id: 't-new',
      orderId: orderRef,
      amount: amount,
      type: type,
      method: method,
      createdAt: DateTime(2026, 7, 18),
      paymentSource: paymentSource,
    );
  }

  @override
  Future<PaymentTransaction> updateTransaction(
    String orderRef,
    String txnId, {
    double? amount,
    String? type,
    String? method,
    String? notes,
    String? paymentSource,
  }) async {
    lastUpdateOrderRef = orderRef;
    lastUpdateTxnId = txnId;
    lastUpdatePaymentSource = paymentSource;
    return PaymentTransaction(
      id: txnId,
      orderId: orderRef,
      amount: amount ?? 0,
      type: type ?? 'deposit',
      method: method ?? 'cash',
      createdAt: DateTime(2026, 7, 18),
      paymentSource: paymentSource,
    );
  }
}

ProviderContainer _containerWithService(_RecordingTxnService service) {
  final container = ProviderContainer(
    overrides: [
      paymentTransactionServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('OrderPaymentTransactionsNotifier.record forwards paymentSource', () {
    test('forwards non-empty paymentSource to the service', () async {
      final service = _RecordingTxnService();
      final container = _containerWithService(service);

      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      await notifier.record(
        amount: 100000,
        type: 'deposit',
        method: 'transfer',
        notes: 'ghi chu',
        paymentSource: VN.paymentSourcePhuongVCB,
      );

      expect(service.lastCreateOrderRef, _testRef);
      expect(
        service.lastCreatePaymentSource,
        VN.paymentSourcePhuongVCB,
        reason: 'record() must forward paymentSource to createTransaction',
      );
    });

    test('omits/null paymentSource is accepted (NFR3)', () async {
      final service = _RecordingTxnService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      await notifier.record(amount: 50000, type: 'deposit', method: 'cash');

      expect(service.lastCreatePaymentSource, isNull,
          reason: 'null paymentSource must be forwarded as null');
    });
  });

  group('OrderPaymentTransactionsNotifier.edit forwards paymentSource', () {
    test('forwards non-empty paymentSource to updateTransaction', () async {
      final service = _RecordingTxnService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      await notifier.edit(
        'txn-42',
        amount: 200000,
        type: 'payment',
        method: 'transfer',
        notes: 'sua',
        paymentSource: VN.paymentSourceAnVCB,
      );

      expect(service.lastUpdateOrderRef, _testRef);
      expect(service.lastUpdateTxnId, 'txn-42');
      expect(service.lastUpdatePaymentSource, VN.paymentSourceAnVCB);
    });

    test('null paymentSource is forwarded to updateTransaction (NFR3)',
        () async {
      final service = _RecordingTxnService();
      final container = _containerWithService(service);
      final notifier = container.read(
        orderPaymentTransactionsProvider(_testRef).notifier,
      );

      await notifier.edit(
        'txn-43',
        amount: 200000,
        type: 'payment',
        method: 'cash',
        notes: '',
      );

      expect(service.lastUpdatePaymentSource, isNull);
    });
  });
}