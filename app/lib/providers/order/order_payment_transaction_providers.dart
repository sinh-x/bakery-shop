import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/payment_transaction_service.dart';
import '../../data/models/payment_transaction.dart';
import '../events_provider.dart';
import 'order_detail_notifier.dart';

class OrderPaymentTransactionsNotifier
    extends AsyncNotifier<List<PaymentTransaction>> {
  final String orderRef;

  OrderPaymentTransactionsNotifier(this.orderRef);

  @override
  Future<List<PaymentTransaction>> build() async {
    final service = ref.read(paymentTransactionServiceProvider);
    return service.listTransactions(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(paymentTransactionServiceProvider);
      return service.listTransactions(orderRef);
    });
  }

  Future<PaymentTransaction> record({
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
    String? paymentSource,
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final txn = await service.createTransaction(
      orderRef,
      amount: amount,
      type: type,
      method: method,
      notes: notes,
      paymentSource: paymentSource,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, txn]);
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return txn;
  }

  Future<PaymentTransaction> edit(
    String txnId, {
    required double amount,
    required String type,
    required String method,
    required String notes,
    String? paymentSource,
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final updated = await service.updateTransaction(
      orderRef,
      txnId,
      amount: amount,
      type: type,
      method: method,
      notes: notes,
      paymentSource: paymentSource,
    );
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }

  Future<void> remove(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    await service.deleteTransaction(orderRef, txnId);
    final current = state.value ?? [];
    state = AsyncData(current.where((t) => t.id != txnId).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
  }

  Future<PaymentTransaction> invalidate(
    String txnId, {
    String reason = '',
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final invalidatedBy = ref.read(loggedByProvider);
    final updated = await service.invalidateTransaction(
      orderRef,
      txnId,
      invalidatedBy: invalidatedBy,
      reason: reason,
    );
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }

  Future<PaymentTransaction> restore(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final updated = await service.restoreTransaction(orderRef, txnId);
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }
}

final orderPaymentTransactionsProvider =
    AsyncNotifierProvider.family<
      OrderPaymentTransactionsNotifier,
      List<PaymentTransaction>,
      String
    >(OrderPaymentTransactionsNotifier.new);