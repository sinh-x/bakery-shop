import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/order_draft.dart';
import '../../../data/models/product.dart';
import '../../../providers/order/order_create_state_provider.dart';
import 'extras_section.dart';
import 'product_picker_page.dart';
import 'selected_items_list.dart';
import 'stage1_empty_state.dart';
import 'stage1_responsive_content.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 1 of the order creation wizard — product selection.
///
/// Two-step flow (DG-214):
/// - Shows a selected-items list with a (+) button.
/// - The (+) button will open a full-screen product picker (Phase 2).
///
/// Phase 2 (DG-214) wires the (+) button to a full-screen `ProductPickerPage`.
/// Single-tap-to-select adds a `DraftOrderItem` and returns to Stage 1; new
/// items appear expanded because `ExpandableItemCard` defaults `_expanded =
/// true`. The picker is reused as-is (no modifications, per guardrails).
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
  /// Working copy of the items list handed to `ProductPickerPage`. The picker
  /// mutates this list in place (appends new `DraftOrderItem`s on single-tap)
  /// and calls [onChanged]; we then commit the list back to the state.
  List<DraftOrderItem> _pickerItems = const [];

  Future<void> _onAddProduct() async {
    // Seed the picker with a deep copy of the current items so edits made to
    // working copies inside the picker do not mutate the live state objects
    // before [onChanged] commits. All mutable fields must be copied to avoid
    // losing details (qty, price, notes, birthday, age, attributes, photos,
    // tien rut) when the picker appends a new item and commits the list.
    final current = ref.read(orderCreateStateProvider).items;
    _pickerItems = current
        .map((i) => DraftOrderItem(
              product: i.product,
              quantity: i.quantity,
              notes: i.notes,
              isBirthday: i.isBirthday,
              age: i.age,
              customUnitPrice: i.customUnitPrice,
              isExtra: i.isExtra,
              isGift: i.isGift,
              attributes: Map<String, dynamic>.from(i.attributes),
              daDuaTienRut: i.daDuaTienRut,
              priceChipId: i.priceChipId,
            )..pendingPhotos = List<XFile>.from(i.pendingPhotos))
        .toList();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductPickerPage(
          selectedItems: _pickerItems,
          onChanged: _commitNewItems,
          initialCategorySlug:
              ref.read(orderCreateStateProvider).selectedCategorySlug,
          onCategorySelected: (slug) => ref
              .read(orderCreateStateProvider.notifier)
              .updateSelectedCategorySlug(slug),
        ),
      ),
    );
  }

  /// Called by the picker when a product is selected. Commits the working
  /// list (which now includes the newly added item) back to the state so
  /// Stage 1 rebuilds with the new `ExpandableItemCard` expanded. Then runs
  /// auto-gift check so tang_kem products >= threshold trigger gift extras.
  void _commitNewItems() {
    ref
        .read(orderCreateStateProvider.notifier)
        .updateItems(List<DraftOrderItem>.from(_pickerItems));
    ref.read(orderCreateStateProvider.notifier).checkAutoGift();
  }

  /// Adds a catalog (phu_kien) extra via [ExtrasSection] chips.
  void _addCatalogExtra(
    Product product,
    int? priceChipId,
    double? customUnitPrice,
  ) {
    ref.read(orderCreateStateProvider.notifier).addCatalogExtra(
          product: product,
          priceChipId: priceChipId,
          customUnitPrice: customUnitPrice,
        );
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

    final content = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SelectedItemsList(
            items: items,
            regularItems: regularItems,
            extraItems: extraItems,
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _ExtrasHeader(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: ExtrasSection(onAddCatalogExtra: _addCatalogExtra),
          ),
        ),
      ],
    );

    return Stage1ResponsiveContent(
      child: Stack(
        children: [
          content,
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
      ),
    );
  }
}

/// Section header for the extras (phu_kien) add-chips in Stage 1.
class _ExtrasHeader extends StatelessWidget {
  const _ExtrasHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        VN.addExtra,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}