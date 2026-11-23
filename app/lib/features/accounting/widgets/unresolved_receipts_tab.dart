import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers/payment_destination_provider.dart';
import '../../../providers/payment_destination_query_provider.dart';
import '../../../shared/labels/accounting.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils.dart' show formatVND;
import '../../../shared/utils/date_formatting.dart';
import 'assign_payment_destination_button.dart';

class UnresolvedReceiptsTab extends ConsumerWidget {
  const UnresolvedReceiptsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(paymentDestinationQueryProvider);
    final queryNotifier = ref.read(paymentDestinationQueryProvider.notifier);
    final provider = unresolvedPaymentDestinationsProvider(query);
    final receipts = ref.watch(provider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              labelText: AccountingLabels.unresolvedSearch,
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: queryNotifier.search,
          ),
        ),
        Expanded(
          child: receipts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text('${SharedLabels.retry}: $error'),
              ),
            ),
            data: (page) => Column(
              children: [
                Text(
                  AccountingLabels.unresolvedSummary(
                    page.total,
                    formatVND(page.amount),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => ref.refresh(provider.future),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (page.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(AccountingLabels.noUnresolvedReceipts),
                          ),
                        for (final receipt in page.items)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextButton(
                                    onPressed: () => context.push(
                                      '/orders/${receipt.orderRef}',
                                    ),
                                    child: Text(
                                      '${receipt.orderRef} · ${receipt.customerName}',
                                    ),
                                  ),
                                  Text(formatVND(receipt.transaction.amount)),
                                  Text(
                                    formatDisplay(
                                      receipt.transaction.createdAt,
                                    ),
                                  ),
                                  if (receipt.transaction.notes.isNotEmpty)
                                    Text(receipt.transaction.notes),
                                  AssignPaymentDestinationButton(
                                    orderRef: receipt.orderRef,
                                    transactionId: receipt.transaction.id,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: query.$2 > 0
                          ? queryNotifier.previousPage
                          : null,
                      child: const Text(AccountingLabels.previousPage),
                    ),
                    TextButton(
                      onPressed: page.hasMore ? queryNotifier.nextPage : null,
                      child: const Text(AccountingLabels.nextPage),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
