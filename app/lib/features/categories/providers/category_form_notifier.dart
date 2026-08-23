import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class CategoryNewDraft {
  const CategoryNewDraft({
    this.name = '',
    this.codePrefix = '',
    this.slug = '',
    this.selectedIcon = '',
    this.isActive = true,
  });

  final String name;
  final String codePrefix;
  final String slug;
  final String selectedIcon;
  final bool isActive;

  CategoryNewDraft copyWith({
    String? name,
    String? codePrefix,
    String? slug,
    String? selectedIcon,
    bool? isActive,
  }) => CategoryNewDraft(
    name: name ?? this.name,
    codePrefix: codePrefix ?? this.codePrefix,
    slug: slug ?? this.slug,
    selectedIcon: selectedIcon ?? this.selectedIcon,
    isActive: isActive ?? this.isActive,
  );
}

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
  CategoryFormNotifier([this.context]);

  final FormDraftContext? context;
  CategoryNewDraft _newDraft = const CategoryNewDraft();
  bool _initialized = false;

  CategoryNewDraft get newDraft => _newDraft;
  CategoryNewDraft get draftSnapshot => _newDraft;
  bool get hasRetainedDraft =>
      context != null &&
      ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<CategoryNewDraft>(context!) !=
          null;

  @override
  CategoryFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDraft = const CategoryNewDraft();
    _initialized = false;
    if (context != null) {
      final retained = ref
          .read(formDraftSessionProvider.notifier)
          .readDraft<CategoryNewDraft>(context!);
      _newDraft = retained ?? const CategoryNewDraft();
      _initialized = retained != null;
    }
    return CategoryFormState(
      selectedIcon: _newDraft.selectedIcon,
      isActive: _newDraft.isActive,
    );
  }

  /// Seed the initial form state from the (optional) [Category] being
  /// edited. Called once from the form's `initState` before any
  /// mutation. Has no effect when in add mode apart from clearing the
  /// editing id.
  void seed({
    int? editingId,
    String? name,
    String? codePrefix,
    String? slug,
    String? icon,
    bool? active,
  }) {
    if (hasRetainedDraft) return;
    if (editingId == null) {
      state = CategoryFormState(selectedIcon: _newDraft.selectedIcon);
      _initialized = true;
      return;
    }
    if (context != null) {
      _newDraft = CategoryNewDraft(
        name: name ?? '',
        codePrefix: codePrefix ?? '',
        slug: slug ?? '',
        selectedIcon: icon ?? '',
        isActive: active ?? true,
      );
    }
    state = CategoryFormState(
      editingId: editingId,
      selectedIcon: icon ?? '',
      isActive: active ?? true,
    );
    _initialized = true;
  }

  void updateNewDraft({String? name, String? codePrefix, String? slug}) {
    _newDraft = _newDraft.copyWith(
      name: name,
      codePrefix: codePrefix,
      slug: slug,
    );
    _retain();
  }

  void clearNewDraft() {
    _newDraft = const CategoryNewDraft();
    state = const CategoryFormState();
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(CategoryNewDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _newDraft = const CategoryNewDraft();
      state = const CategoryFormState();
    }
    return cleared;
  }

  void setSelectedIcon(String value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(selectedIcon: value);
      _retain();
    }
    state = state.copyWith(selectedIcon: value);
  }

  void setIsActive(bool value) {
    _newDraft = _newDraft.copyWith(isActive: value);
    _retain();
    state = state.copyWith(isActive: value);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  void _retain() {
    if (context != null && _initialized) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(context!, _newDraft);
    }
  }
}

/// Provider for the category-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final categoryFormProvider =
    NotifierProvider<CategoryFormNotifier, CategoryFormState>(
      CategoryFormNotifier.new,
    );

final contextualCategoryFormProvider =
    NotifierProvider.family<
      CategoryFormNotifier,
      CategoryFormState,
      FormDraftContext
    >(CategoryFormNotifier.new);
