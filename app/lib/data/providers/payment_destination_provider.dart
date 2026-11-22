import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/payment_destination_service.dart';
import 'accounting_provider.dart';
import 'cash_drawer_provider.dart';
import 'order/order_detail_notifier.dart';
import 'order/order_payment_transaction_providers.dart';

final unresolvedPaymentDestinationsProvider =
    FutureProvider.family<UnresolvedReceiptPage, (String, int)>((ref, query) {
      return ref
          .watch(paymentDestinationServiceProvider)
          .list(search: query.$1, offset: query.$2);
    });

class AssignPaymentDestinationNotifier extends AsyncNotifier<void> {
  AssignPaymentDestinationNotifier(this.identity);
  final (String, String) identity;

  @override
  FutureOr<void> build() {}

  Future<bool> assign(String method, String paymentSource) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(paymentDestinationServiceProvider)
          .assign(
            identity.$1,
            identity.$2,
            method: method,
            paymentSource: paymentSource,
          );
      ref.invalidate(unresolvedPaymentDestinationsProvider);
      ref.invalidate(orderPaymentTransactionsProvider(identity.$1));
      ref.invalidate(orderDetailProvider(identity.$1));
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(journalEntriesProvider);
      ref.invalidate(cashDrawerStatusProvider);
      ref.invalidate(cashDrawerAccountingBalance1101Provider);
    });
    return !state.hasError;
  }
}

final assignPaymentDestinationProvider =
    AsyncNotifierProvider.family<
      AssignPaymentDestinationNotifier,
      void,
      (String, String)
    >(AssignPaymentDestinationNotifier.new);
