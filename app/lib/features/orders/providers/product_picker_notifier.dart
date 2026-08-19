import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';

/// Product-picker page selection state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_selectedIds` and `_multiSelectMode` fields previously mutated
/// via `setState` inside `_ProductPickerPageState`. The widget reads
/// [productPickerProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class ProductPickerState {
  const ProductPickerState({
    this.selectedIds = const <int>{},
    this.multiSelectMode = false,
  });

  final Set<int> selectedIds;
  final bool multiSelectMode;

  ProductPickerState copyWith({
    Set<int>? selectedIds,
    bool? multiSelectMode,
  }) =>
      ProductPickerState(
        selectedIds: selectedIds ?? this.selectedIds,
        multiSelectMode: multiSelectMode ?? this.multiSelectMode,
      );
}

class ProductPickerNotifier extends Notifier<ProductPickerState> {
  Set<int>? _initialSelectedIds;

  /// Seed the initial selection from the parent's `selectedItems` list.
  /// Called once from the widget's `initState` before any mutation. Updates
  /// the state so the seeded selection is visible on the first build.
  void seedInitial(Set<int> ids) {
    _initialSelectedIds = Set<int>.from(ids);
    if (!setEquals(state.selectedIds, _initialSelectedIds!) ||
        state.multiSelectMode) {
      state = ProductPickerState(
        selectedIds: Set<int>.from(_initialSelectedIds!),
      );
    }
  }

  @override
  ProductPickerState build() => ProductPickerState(
        selectedIds:
            _initialSelectedIds != null ? Set<int>.from(_initialSelectedIds!) : const <int>{},
      );

  void toggleProduct(Product product) {
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(product.id)) {
      next.remove(product.id);
    } else {
      next.add(product.id);
    }
    state = state.copyWith(selectedIds: next);
  }

  void enterMultiSelectMode(Product product) {
    final next = Set<int>.from(state.selectedIds)..add(product.id);
    state = state.copyWith(selectedIds: next, multiSelectMode: true);
  }
}

final productPickerProvider =
    NotifierProvider<ProductPickerNotifier, ProductPickerState>(
        ProductPickerNotifier.new);