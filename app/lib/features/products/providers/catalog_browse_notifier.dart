import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_browse_photo.dart';

/// State for the catalog browse screen (DG-404 Phase 4.7 / FR2).
///
/// Owns the selected tags, selected category slugs, computed filter key,
/// select-mode flag, selected photo ids, and bulk-in-progress flag
/// previously held as `setState` fields inside `_CatalogBrowseScreenState`.
class CatalogBrowseState {
  const CatalogBrowseState({
    this.selectedTags = const <String>{},
    this.selectedCategorySlugs = const <String>{},
    this.filterKey = '',
    this.selectMode = false,
    this.selectedPhotoIds = const <int>{},
    this.bulkInProgress = false,
  });

  final Set<String> selectedTags;
  final Set<String> selectedCategorySlugs;
  final String filterKey;
  final bool selectMode;
  final Set<int> selectedPhotoIds;
  final bool bulkInProgress;

  CatalogBrowseState copyWith({
    Set<String>? selectedTags,
    Set<String>? selectedCategorySlugs,
    String? filterKey,
    bool? selectMode,
    Set<int>? selectedPhotoIds,
    bool? bulkInProgress,
  }) {
    return CatalogBrowseState(
      selectedTags: selectedTags ?? this.selectedTags,
      selectedCategorySlugs:
          selectedCategorySlugs ?? this.selectedCategorySlugs,
      filterKey: filterKey ?? this.filterKey,
      selectMode: selectMode ?? this.selectMode,
      selectedPhotoIds: selectedPhotoIds ?? this.selectedPhotoIds,
      bulkInProgress: bulkInProgress ?? this.bulkInProgress,
    );
  }
}

/// `Notifier` that owns the catalog browse screen state
/// (DG-404 Phase 4.7 / FR2).
class CatalogBrowseNotifier extends Notifier<CatalogBrowseState> {
  @override
  CatalogBrowseState build() => const CatalogBrowseState();

  void clearSelection() {
    state = state.copyWith(
      selectMode: false,
      selectedPhotoIds: const <int>{},
    );
  }

  void toggleSelectMode() {
    final nextSelectMode = !state.selectMode;
    state = state.copyWith(
      selectMode: nextSelectMode,
      selectedPhotoIds:
          nextSelectMode ? state.selectedPhotoIds : const <int>{},
    );
  }

  void selectAll20(List<CatalogBrowsePhoto> photos) {
    final count = photos.length >= 20 ? 20 : photos.length;
    state = state.copyWith(
      selectedPhotoIds: photos.take(count).map((p) => p.id).toSet(),
    );
  }

  void onPhotoToggle(int photoId, bool selected) {
    final next = Set<int>.from(state.selectedPhotoIds);
    if (selected) {
      if (next.length >= 20) {
        // Caller is responsible for showing the snackbar; notifier just
        // refuses to exceed the cap.
        return;
      }
      next.add(photoId);
    } else {
      next.remove(photoId);
    }
    state = state.copyWith(selectedPhotoIds: next);
  }

  void toggleTag(String tag) {
    final next = Set<String>.from(state.selectedTags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    state = state.copyWith(
      selectedTags: next,
      filterKey: _computeFilterKeyAfterTagChange(next, state.selectedCategorySlugs),
      selectedPhotoIds: const <int>{},
    );
  }

  void toggleCategory(String slug) {
    final next = Set<String>.from(state.selectedCategorySlugs);
    if (next.contains(slug)) {
      next.remove(slug);
    } else {
      next.add(slug);
    }
    state = state.copyWith(
      selectedCategorySlugs: next,
      filterKey: _computeFilterKeyAfterTagChange(state.selectedTags, next),
      selectedPhotoIds: const <int>{},
    );
  }

  void clearAll() {
    state = state.copyWith(
      selectedTags: const <String>{},
      selectedCategorySlugs: const <String>{},
      filterKey: _computeFilterKeyAfterTagChange(<String>{}, <String>{}),
      selectedPhotoIds: const <int>{},
    );
  }

  String _computeFilterKeyAfterTagChange(
    Set<String> tags,
    Set<String> cats,
  ) {
    final sortedTags = tags.toList()..sort();
    final sortedCats = cats.toList()..sort();
    final tagPart = 'tags:${sortedTags.join('|')}';
    final catPart = 'cats:${sortedCats.join('|')}';
    return '$tagPart;$catPart';
  }

  void setBulkInProgress(bool value) =>
      state = state.copyWith(bulkInProgress: value);
}

/// Provider for the catalog browse screen state.
final catalogBrowseNotifierProvider =
    NotifierProvider<CatalogBrowseNotifier, CatalogBrowseState>(
        CatalogBrowseNotifier.new);