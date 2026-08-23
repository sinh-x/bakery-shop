import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const catalogTagCreateContext = FormDraftContext(
  formType: 'catalog-tag',
  mode: FormDraftMode.create,
);

/// Form state for the add-catalog-tag dialog (DG-404 Phase 4.7).
///
/// Owns the `selectedCategory` field previously held as a `setState`
/// field inside `_AddTagDialogState`. The widget reads
/// [catalogTagFormProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class CatalogTagFormState {
  const CatalogTagFormState({
    this.selectedCategory,
    this.key = '',
    this.label = '',
  });

  final String? selectedCategory;
  final String key;
  final String label;

  bool get isDirty =>
      selectedCategory != null || key.isNotEmpty || label.isNotEmpty;

  CatalogTagFormState copyWith({
    String? selectedCategory,
    String? key,
    String? label,
    bool clearSelectedCategory = false,
  }) {
    return CatalogTagFormState(
      selectedCategory: clearSelectedCategory
          ? null
          : (selectedCategory ?? this.selectedCategory),
      key: key ?? this.key,
      label: label ?? this.label,
    );
  }
}

/// `Notifier` that owns the add-catalog-tag dialog form state
/// (DG-404 Phase 4.7). Sync state because all mutations are local.
class CatalogTagFormNotifier extends Notifier<CatalogTagFormState> {
  @override
  CatalogTagFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    final drafts = ref.read(formDraftSessionProvider);
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(catalogTagCreateContext) ?? false) &&
          !next.containsKey(catalogTagCreateContext)) {
        state = const CatalogTagFormState();
      }
    });
    return drafts[catalogTagCreateContext] as CatalogTagFormState? ??
        const CatalogTagFormState();
  }

  void setSelectedCategory(String? value) => _retain(
    state.copyWith(
      selectedCategory: value,
      clearSelectedCategory: value == null,
    ),
  );

  void setKey(String value) => _retain(state.copyWith(key: value));

  void setLabel(String value) => _retain(state.copyWith(label: value));

  void _retain(CatalogTagFormState next) {
    state = next;
    final registry = ref.read(formDraftSessionProvider.notifier);
    if (next.isDirty) {
      registry.retainDraft(catalogTagCreateContext, next);
    } else {
      registry.clearDraft(catalogTagCreateContext);
    }
  }

  void clear() {
    ref
        .read(formDraftSessionProvider.notifier)
        .clearDraft(catalogTagCreateContext);
    state = const CatalogTagFormState();
  }
}

/// Provider for the add-catalog-tag dialog form state. The widget reads
/// this and calls the notifier's mutators; no `setState` is required.
final catalogTagFormProvider =
    NotifierProvider<CatalogTagFormNotifier, CatalogTagFormState>(
      CatalogTagFormNotifier.new,
    );

class CatalogTagFormOperationNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(formDraftSessionEpochProvider);
    return false;
  }

  void setSaving(bool value) => state = value;
}

final catalogTagFormOperationProvider =
    NotifierProvider<CatalogTagFormOperationNotifier, bool>(
      CatalogTagFormOperationNotifier.new,
    );
