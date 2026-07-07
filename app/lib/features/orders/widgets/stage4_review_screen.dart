import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage4ReviewScreen extends ConsumerWidget {
  const Stage4ReviewScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
    this.isProcessing = false,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final bool isProcessing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderCreateStateProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OrdersLabels.reviewSummary,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  OrdersLabels.checkoutReviewHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                StageSummaryCard(
                  items: state.items,
                  wizardData: state.wizardData,
                  source: state.source,
                  dueDate: state.dueDate,
                  dueTime: state.dueTime,
                  showProducts: true,
                  showCustomer: true,
                  showDelivery: true,
                ),
              ],
            ),
          ),
        ),
        _buildNavigation(),
      ],
    );
  }

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: isProcessing ? null : onSubmit,
            child: isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(OrdersLabels.reviewCreateOrder),
          ),
        ],
      ),
    );
  }
}
