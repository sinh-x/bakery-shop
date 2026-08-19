import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';

/// State for the catalog photo viewer screen (DG-404 Phase 4.7 / FR2).
///
/// Owns the `currentIndex`, `downloading`, and `sharing` flags previously
/// held as `setState` fields inside `_CatalogPhotoViewerState`.
class CatalogPhotoViewerState {
  const CatalogPhotoViewerState({
    this.currentIndex = 0,
    this.downloading = false,
    this.sharing = false,
  });

  final int currentIndex;
  final bool downloading;
  final bool sharing;

  CatalogPhotoViewerState copyWith({
    int? currentIndex,
    bool? downloading,
    bool? sharing,
  }) {
    return CatalogPhotoViewerState(
      currentIndex: currentIndex ?? this.currentIndex,
      downloading: downloading ?? this.downloading,
      sharing: sharing ?? this.sharing,
    );
  }
}

/// `Notifier` that owns the catalog photo viewer state (DG-404 Phase 4.7).
class CatalogPhotoViewerNotifier extends Notifier<CatalogPhotoViewerState> {
  @override
  CatalogPhotoViewerState build() => const CatalogPhotoViewerState();

  void setCurrentIndex(int index) =>
      state = state.copyWith(currentIndex: index);

  void setDownloading(bool value) =>
      state = state.copyWith(downloading: value);

  void setSharing(bool value) => state = state.copyWith(sharing: value);
}

/// Provider for the catalog photo viewer state.
final catalogPhotoViewerProvider =
    NotifierProvider<CatalogPhotoViewerNotifier, CatalogPhotoViewerState>(
        CatalogPhotoViewerNotifier.new);

/// State for the edit-caption bottom sheet (DG-404 Phase 4.7 / FR2).
///
/// Owns the `selectedTags` set and `saving` flag previously held as
/// `setState` fields inside `_EditCaptionSheetState`.
class CatalogEditCaptionState {
  const CatalogEditCaptionState({
    this.selectedTags = const <String>{},
    this.saving = false,
  });

  final Set<String> selectedTags;
  final bool saving;

  CatalogEditCaptionState copyWith({
    Set<String>? selectedTags,
    bool? saving,
  }) {
    return CatalogEditCaptionState(
      selectedTags: selectedTags ?? this.selectedTags,
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the edit-caption sheet state (DG-404 Phase 4.7).
class CatalogEditCaptionNotifier extends Notifier<CatalogEditCaptionState> {
  @override
  CatalogEditCaptionState build() => const CatalogEditCaptionState();

  /// Seed the initial selected tags from the photo's existing tags.
  void seed(CatalogPhoto photo) {
    if (photo.tags.isEmpty) {
      state = const CatalogEditCaptionState();
      return;
    }
    final tags = <String>{};
    tags.addAll(
      photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
    );
    state = CatalogEditCaptionState(selectedTags: tags);
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

/// Provider for the edit-caption sheet state.
final catalogEditCaptionProvider =
    NotifierProvider<CatalogEditCaptionNotifier, CatalogEditCaptionState>(
        CatalogEditCaptionNotifier.new);