import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../data/api/payment_transaction_service.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/payment_transaction_photo.dart';
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

  // ── Per-transaction photo (DG-410 Phase 3) ─────────────────────────────────
  //
  // The record-payment sheet calls [linkPhoto] with the hash of the photo it
  // just uploaded to the order-level `chuyen-khoan` strip, against the id
  // returned by [record] (FR2). The edit / detail sheets use [attachPhoto] /
  // [detachPhoto] for add/replace/remove (FR3). After any mutation the lazy
  // [transactionPhotoProvider] is invalidated so the detail sheet re-fetches.

  Future<PaymentTransactionPhoto> linkPhoto(
    String txnId,
    String photoHash,
  ) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final link = await service.linkTransactionPhoto(orderRef, txnId, photoHash);
    ref.invalidate(transactionPhotoProvider((orderRef, txnId)));
    return link;
  }

  Future<PaymentTransactionPhoto> attachPhoto(String txnId, XFile file) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final link = await service.attachTransactionPhoto(orderRef, txnId, file);
    ref.invalidate(transactionPhotoProvider((orderRef, txnId)));
    return link;
  }

  Future<void> detachPhoto(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    await service.detachTransactionPhoto(orderRef, txnId);
    ref.invalidate(transactionPhotoProvider((orderRef, txnId)));
  }
}

final orderPaymentTransactionsProvider =
    AsyncNotifierProvider.family<
      OrderPaymentTransactionsNotifier,
      List<PaymentTransaction>,
      String
    >(OrderPaymentTransactionsNotifier.new);

/// Lazy fetch of a single transaction's attached photo (NFR3).
///
/// Fetched only when the transaction detail sheet opens — no extra fetch on
/// tab switch. Returns `null` when the transaction has no photo (backend 404
/// is normalized to `null`). Keyed by `(orderRef, txnId)`.
final transactionPhotoProvider =
    FutureProvider.family<PaymentTransactionPhoto?, (String, String)>(
  (ref, key) async {
    final (orderRef, txnId) = key;
    final service = ref.read(paymentTransactionServiceProvider);
    try {
      return await service.getTransactionPhoto(orderRef, txnId);
    } on DioException catch (e) {
      // 404 means no photo attached — normalize to null (NFR3 lazy fetch).
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  },
);