import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'section_header.dart';
import 'stage1_responsive_content.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage4ReviewScreen extends ConsumerWidget {
  Stage4ReviewScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
    this.isProcessing = false,
    required this.orderStateProvider,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final bool isProcessing;
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState> orderStateProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderStateProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: Stage1ResponsiveContent(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(OrdersLabels.reviewSummary),
                  Text(
                    OrdersLabels.checkoutReviewHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ProductSummaryCard(items: state.items),
                  CustomerSummaryCard(
                    wizardData: state.wizardData,
                    source: state.source,
                  ),
                  DeliverySummaryCard(
                    wizardData: state.wizardData,
                    dueDate: state.dueDate,
                    dueTime: state.dueTime,
                  ),
                ],
              ),
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
