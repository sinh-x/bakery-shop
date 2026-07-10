import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import '../../order_edit/widgets/edit_extras_section.dart';
import '../../order_edit/widgets/work_items_section.dart';
import '../product_picker_page.dart';
import '../section_header.dart';
import '../stage1_empty_state.dart';
import '../stage1_responsive_content.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 1 of the order edit wizard — product selection (work items + extras).
///
/// FR11/FR14: aligned with create's Stage 1 layout — wrapped in
/// `Stage1ResponsiveContent`, shows a `Stage1EmptyState` matching create when
/// no WorkItems exist, and uses the shared `SectionHeader`. The
/// `WorkItemsSection`/`EditExtrasSection` behavior is preserved; server-side
/// WorkItems remain the data source.
class EditStage1Product extends ConsumerStatefulWidget {
  const EditStage1Product({
    super.key,
    required this.orderRef,
    required this.onBack,
    required this.onContinue,
  });

  final String orderRef;
  final VoidCallback? onBack;
  final VoidCallback onContinue;

  @override
  ConsumerState<EditStage1Product> createState() => _EditStage1ProductState();
}

class _EditStage1ProductState extends ConsumerState<EditStage1Product> {
  final _pendingNewItems = <DraftOrderItem>[];

  Future<void> _openProductPicker() async {
    _pendingNewItems.clear();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductPickerPage(
          selectedItems: _pendingNewItems,
          onChanged: _commitNewItems,
        ),
      ),
    );
  }

  void _commitNewItems() {
    final toAdd = List<DraftOrderItem>.from(_pendingNewItems);
    for (final draft in toAdd) {
      ref.read(orderWorkItemsProvider(widget.orderRef).notifier).add(
            productName: draft.product.name,
            productId: draft.product.productCode,
            quantity: draft.quantity,
            unitPrice: draft.unitPrice,
            notes: draft.notes,
            attributes: draft.attributes,
            priceChipId: draft.priceChipId,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workItemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final workItems = workItemsAsync.value ?? const <WorkItem>[];
    final hasRegular = workItems.any((i) => !i.isExtra);
    final hasExtras = workItems.any((i) => i.isExtra);
    // Only show the empty state once work items have loaded and are truly
    // empty. During the initial load (`value` is null) we render the content
    // scaffold so the empty state does not flash before data arrives.
    final isLoaded = workItemsAsync.hasValue;
    final isEmpty = isLoaded && !hasRegular && !hasExtras;

    if (isEmpty) {
      return Column(
        children: [
          Expanded(child: Stage1EmptyState(onAddProduct: _openProductPicker)),
          _buildStageNavigation(),
        ],
      );
    }

    return Stage1ResponsiveContent(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(VN.workItemsSection),
                  WorkItemsSection(
                    orderRef: widget.orderRef,
                    onAddTap: _openProductPicker,
                  ),
                  const SizedBox(height: 20),
                  EditExtrasSection(orderRef: widget.orderRef),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          _buildStageNavigation(),
        ],
      ),
    );
  }

  Widget _buildStageNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (widget.onBack != null)
            OutlinedButton(
              onPressed: widget.onBack,
              child: const Text(OrdersLabels.backLabel),
            )
          else
            const SizedBox(width: 0),
          const Spacer(),
          FilledButton(
            onPressed: widget.onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}