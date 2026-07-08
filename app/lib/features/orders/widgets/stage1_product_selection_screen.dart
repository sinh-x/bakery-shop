import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'selected_items_list.dart';
import 'stage1_empty_state.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 1 of the order creation wizard — product selection.
///
/// Two-step flow (DG-214):
/// - Shows a selected-items list with a (+) button.
/// - The (+) button will open a full-screen product picker (Phase 2).
///
/// Phase 1 only delivers the layout: empty state, (+) button, and reuse of
/// `ExpandableItemCard` via [SelectedItemsList]. The inline product grid has
/// been removed and the `Expanded`/`CustomScrollView` layout conflict fixed
/// (the parent already provides an `Expanded` for the `PageView`).
class Stage1ProductSelectionScreen extends ConsumerStatefulWidget {
  const Stage1ProductSelectionScreen({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  ConsumerState<Stage1ProductSelectionScreen> createState() =>
      _Stage1ProductSelectionScreenState();
}

class _Stage1ProductSelectionScreenState
    extends ConsumerState<Stage1ProductSelectionScreen> {
  void _onAddProduct() {
    // Phase 2 (DG-214) will wire this to ProductPickerPage.
    // Intentionally a no-op stub for Phase 1.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderCreateStateProvider);
    final items = state.items;
    final regularItems = items.where((i) => !i.isExtra).toList();
    final extraItems = items.where((i) => i.isExtra).toList();

    if (regularItems.isEmpty && extraItems.isEmpty) {
      return Stage1EmptyState(onAddProduct: _onAddProduct);
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SelectedItemsList(
                items: items,
                regularItems: regularItems,
                extraItems: extraItems,
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'stage1_add_product',
            tooltip: OrdersLabels.stage1AddProductHint,
            onPressed: _onAddProduct,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}