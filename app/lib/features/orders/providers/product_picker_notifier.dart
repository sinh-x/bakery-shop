import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

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

  ProductPickerState copyWith({Set<int>? selectedIds, bool? multiSelectMode}) =>
      ProductPickerState(
        selectedIds: selectedIds ?? this.selectedIds,
        multiSelectMode: multiSelectMode ?? this.multiSelectMode,
      );
}

class ProductPickerNotifier extends Notifier<ProductPickerState> {
  ProductPickerNotifier(this.context);

  final FormDraftContext context;

  /// Seed the initial selection from the parent's `selectedItems` list.
  /// Called once from the widget's `initState` before any mutation. Updates
  /// the state so the seeded selection is visible on the first build.
  void seedInitial(Set<int> ids) {
    if (ref.read(formDraftSessionProvider).containsKey(context)) return;
    if (!setEquals(state.selectedIds, ids) || state.multiSelectMode) {
      state = ProductPickerState(selectedIds: Set<int>.from(ids));
    }
  }

  @override
  ProductPickerState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const ProductPickerState(),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const ProductPickerState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<ProductPickerState>(context) ??
        const ProductPickerState();
  }

  void _set(ProductPickerState next) {
    state = next;
    ref.read(formDraftSessionProvider.notifier).retainDraft(context, next);
  }

  void toggleProduct(Product product) {
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(product.id)) {
      next.remove(product.id);
    } else {
      next.add(product.id);
    }
    _set(state.copyWith(selectedIds: next));
  }

  void enterMultiSelectMode(Product product) {
    final next = Set<int>.from(state.selectedIds)..add(product.id);
    _set(state.copyWith(selectedIds: next, multiSelectMode: true));
  }

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const ProductPickerState();
  }
}

final productPickerProvider =
    NotifierProvider.family<
      ProductPickerNotifier,
      ProductPickerState,
      FormDraftContext
    >(ProductPickerNotifier.new);
