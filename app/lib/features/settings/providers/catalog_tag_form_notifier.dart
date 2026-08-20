import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form state for the add-catalog-tag dialog (DG-404 Phase 4.7).
///
/// Owns the `selectedCategory` field previously held as a `setState`
/// field inside `_AddTagDialogState`. The widget reads
/// [catalogTagFormProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class CatalogTagFormState {
  const CatalogTagFormState({this.selectedCategory});

  final String? selectedCategory;

  CatalogTagFormState copyWith({String? selectedCategory}) {
    return CatalogTagFormState(
      selectedCategory: selectedCategory ?? this.selectedCategory,
    );
  }
}

/// `Notifier` that owns the add-catalog-tag dialog form state
/// (DG-404 Phase 4.7). Sync state because all mutations are local.
class CatalogTagFormNotifier extends Notifier<CatalogTagFormState> {
  @override
  CatalogTagFormState build() => const CatalogTagFormState();

  void setSelectedCategory(String? value) =>
      state = state.copyWith(selectedCategory: value);
}

/// Provider for the add-catalog-tag dialog form state. The widget reads
/// this and calls the notifier's mutators; no `setState` is required.
final catalogTagFormProvider =
    NotifierProvider<CatalogTagFormNotifier, CatalogTagFormState>(
  CatalogTagFormNotifier.new,
);