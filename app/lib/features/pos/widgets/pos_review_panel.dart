import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../../orders/widgets/stage1_responsive_content.dart';
import '../../orders/widgets/stage_summary_card.dart';

/// POS Stage 4 review panel (DG-218 Phase 4, FR-6). Now review-only: it renders
/// the same unified summary cards (`ProductSummaryCard` /
/// `CustomerSummaryCard` / `DeliverySummaryCard`) as the order-create wizard
/// Stage 4 and contains NO payment selector. The payment selection (cash/
/// transfer + transfer photo) is presented as a dedicated step after this
/// review (see `PosPaymentStep`).
///
/// The continue button advances to the payment step; the back button returns
/// to the previous stage (Stage 2 for pickup, Stage 3 for delivery).
class PosReviewPanel extends ConsumerWidget {
  const PosReviewPanel({
    super.key,
    required this.onBack,
    required this.onContinue,
    required this.orderStateProvider,
    this.onFastPath,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState> orderStateProvider;

  /// DG-370 Phase 5.6-c1 (UX-6): optional "Giao ngay & Thanh toán" fast-path
  /// callback. When provided, a button is rendered between "Quay lại" and
  /// "Tiếp tục" so the user can jump directly to Stage 5 with Giao ngay
  /// walk-in defaults from the Stage 4 review.
  final VoidCallback? onFastPath;

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
                  Text(
                    OrdersLabels.reviewSummary,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
          // DG-370 Phase 5.6-c1 (UX-6): "Giao ngay & Thanh toán" fast-path
          // button between "Quay lại" and "Tiếp tục".
          if (onFastPath != null) ...[
            FilledButton.icon(
              onPressed: onFastPath,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text(OrdersLabels.posGiaoNgayThanhToan),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton(
            onPressed: onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}

