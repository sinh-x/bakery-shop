import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';

/// State for the edit-catalog-tags bottom sheet (DG-404 Phase 4.9 / FR2).
///
/// Owns the `selectedTags` set and `saving` flag previously held as
/// `setState` fields inside `_EditCatalogTagsSheetState`. Mirrors
/// `CatalogEditCaptionNotifier` from `catalog_photo_viewer_notifier.dart`.
class CatalogTagEditState {
  const CatalogTagEditState({
    this.selectedTags = const <String>{},
    this.saving = false,
  });

  final Set<String> selectedTags;
  final bool saving;

  CatalogTagEditState copyWith({
    Set<String>? selectedTags,
    bool? saving,
  }) {
    return CatalogTagEditState(
      selectedTags: selectedTags ?? this.selectedTags,
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the edit-catalog-tags sheet state
/// (DG-404 Phase 4.9 / FR2).
class CatalogTagEditNotifier extends Notifier<CatalogTagEditState> {
  @override
  CatalogTagEditState build() => const CatalogTagEditState();

  /// Seed the initial selected tags from the photo's existing tags.
  void seed(CatalogPhoto photo) {
    if (photo.tags.isEmpty) {
      state = const CatalogTagEditState();
      return;
    }
    final tags = <String>{};
    tags.addAll(
      photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
    );
    state = CatalogTagEditState(selectedTags: tags);
  }

  void toggleTag(String tag) {
    final next = Set<String>.from(state.selectedTags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    state = state.copyWith(selectedTags: next);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the edit-catalog-tags sheet state.
final catalogTagEditProvider =
    NotifierProvider<CatalogTagEditNotifier, CatalogTagEditState>(
        CatalogTagEditNotifier.new);