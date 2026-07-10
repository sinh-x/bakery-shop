import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/models/order_draft.dart';
import '../order_photo_section.dart';
import '../order_wizard.dart';
import '../section_header.dart';
import '../stage1_responsive_content.dart';
import '../stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 4 of the order edit wizard — review (summary + order photos + save).
///
/// FR13/FR14: aligned with create's Stage 4 layout — wrapped in
/// `Stage1ResponsiveContent`, uses the shared `SectionHeader` for the review
/// title (replacing the inline `Text`), and preserves the order-level
/// `OrderPhotoSection`.
class EditStage4Review extends ConsumerWidget {
  const EditStage4Review({
    super.key,
    required this.orderRef,
    required this.wizardSnapshot,
    required this.summaryItems,
    required this.dueDate,
    required this.dueTime,
    required this.onSave,
    required this.onBack,
    required this.isProcessing,
  });

  final String orderRef;
  final OrderWizardData wizardSnapshot;
  final List<DraftOrderItem> summaryItems;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final VoidCallback onSave;
  final VoidCallback onBack;
  final bool isProcessing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  ProductSummaryCard(items: summaryItems),
                  CustomerSummaryCard(
                    wizardData: wizardSnapshot,
                    source: wizardSnapshot.source,
                  ),
                  DeliverySummaryCard(
                    wizardData: wizardSnapshot,
                    dueDate: dueDate,
                    dueTime: dueTime,
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader(VN.orderPhotos),
                  OrderPhotoSection(
                    orderRef: orderRef,
                    baseUrl: ref.watch(apiBaseUrlProvider),
                    orderLevelOnly: true,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
        _buildStageNavigation(),
      ],
    );
  }

  Widget _buildStageNavigation() {
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
            onPressed: isProcessing ? null : onSave,
            child: isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.save),
          ),
        ],
      ),
    );
  }
}