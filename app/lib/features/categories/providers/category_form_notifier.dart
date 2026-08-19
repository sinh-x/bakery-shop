import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form state for the category add/edit bottom sheet (DG-404 Phase 4.7).
///
/// Holds the fields previously mutated via `setState` inside
/// `_CategoryFormState`: `selectedIcon`, `isActive`, and `saving`. The
/// widget reads [categoryFormProvider] and invokes the notifier's
/// mutators; no `setState` is required. `TextEditingController`-backed
/// fields (name, codePrefix, slug) remain on the widget (acceptable use).
class CategoryFormState {
  const CategoryFormState({
    this.selectedIcon = '',
    this.isActive = true,
    this.saving = false,
    this.editingId,
  });

  final String selectedIcon;
  final bool isActive;
  final bool saving;
  final int? editingId;

  bool get editing => editingId != null;

  CategoryFormState copyWith({
    String? selectedIcon,
    bool? isActive,
    bool? saving,
    int? editingId,
  }) {
    return CategoryFormState(
      selectedIcon: selectedIcon ?? this.selectedIcon,
      isActive: isActive ?? this.isActive,
      saving: saving ?? this.saving,
      editingId: editingId ?? this.editingId,
    );
  }
}

/// `Notifier` that owns the category-form state (DG-404 Phase 4.7).
///
/// All mutations that previously lived in `setState` closures inside
/// `_CategoryFormState` are now exposed as notifier methods. The widget
/// reads the state via [categoryFormProvider] and rebuilds on change —
/// no `setState` is required.
class CategoryFormNotifier extends Notifier<CategoryFormState> {
  @override
  CategoryFormState build() => const CategoryFormState();

  /// Seed the initial form state from the (optional) [Category] being
  /// edited. Called once from the form's `initState` before any
  /// mutation. Has no effect when in add mode apart from clearing the
  /// editing id.
  void seed({int? editingId, String? icon, bool? active}) {
    state = CategoryFormState(
      editingId: editingId,
      selectedIcon: icon ?? '',
      isActive: active ?? true,
    );
  }

  void setSelectedIcon(String value) =>
      state = state.copyWith(selectedIcon: value);

  void setIsActive(bool value) =>
      state = state.copyWith(isActive: value);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the category-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final categoryFormProvider =
    NotifierProvider<CategoryFormNotifier, CategoryFormState>(
    CategoryFormNotifier.new);