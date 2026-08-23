import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

FormDraftContext catalogTagEditContext(int productId, int photoId) =>
    FormDraftContext(
      formType: 'catalog-photo-tag-edit',
      mode: FormDraftMode.edit,
      entityId: photoId.toString(),
      productId: productId.toString(),
    );

/// State for the edit-catalog-tags bottom sheet (DG-404 Phase 4.9 / FR2).
///
/// Owns the `selectedTags` set and `saving` flag previously held as
/// `setState` fields inside `_EditCatalogTagsSheetState`. Mirrors
/// `CatalogEditCaptionNotifier` from `catalog_photo_viewer_notifier.dart`.
class CatalogTagEditState {
  const CatalogTagEditState({
    this.caption = '',
    this.selectedTags = const <String>{},
    this.saving = false,
  });

  final String caption;
  final Set<String> selectedTags;
  final bool saving;

  CatalogTagEditState copyWith({
    String? caption,
    Set<String>? selectedTags,
    bool? saving,
  }) {
    return CatalogTagEditState(
      caption: caption ?? this.caption,
      selectedTags: selectedTags ?? this.selectedTags,
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the edit-catalog-tags sheet state
/// (DG-404 Phase 4.9 / FR2).
class CatalogTagEditNotifier extends Notifier<CatalogTagEditState> {
  CatalogTagEditNotifier(this.context);

  final FormDraftContext context;
  CatalogTagEditState _seededState = const CatalogTagEditState();

  @override
  CatalogTagEditState build() {
    ref.watch(formDraftSessionEpochProvider);
    final drafts = ref.read(formDraftSessionProvider);
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = _seededState;
      }
    });
    return drafts[context] as CatalogTagEditState? ?? _seededState;
  }

  bool get hasRetainedDraft =>
      ref.read(formDraftSessionProvider).containsKey(context);

  /// Seed the initial selected tags from the photo's existing tags.
  void seed(CatalogPhoto photo) {
    if (hasRetainedDraft) return;
    if (photo.tags.isEmpty) {
      _seededState = CatalogTagEditState(caption: photo.caption);
      state = _seededState;
      return;
    }
    final tags = <String>{};
    tags.addAll(
      photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
    );
    _seededState = CatalogTagEditState(
      caption: photo.caption,
      selectedTags: tags,
    );
    state = _seededState;
  }

  void setCaption(String value) => _retain(state.copyWith(caption: value));

  void toggleTag(String tag) {
    final next = Set<String>.from(state.selectedTags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    _retain(state.copyWith(selectedTags: next));
  }

  void _retain(CatalogTagEditState next) {
    state = next;
    final registry = ref.read(formDraftSessionProvider.notifier);
    if (next.caption == _seededState.caption &&
        setEquals(next.selectedTags, _seededState.selectedTags)) {
      registry.clearDraft(context);
    } else {
      registry.retainDraft(context, next.copyWith(saving: false));
    }
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  void resetOperation() => state = state.copyWith(saving: false);

  void clear() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const CatalogTagEditState();
  }
}

/// Provider for the edit-catalog-tags sheet state.
final catalogTagEditProvider =
    NotifierProvider.family<
      CatalogTagEditNotifier,
      CatalogTagEditState,
      FormDraftContext
    >(CatalogTagEditNotifier.new);
