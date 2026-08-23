import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

FormDraftContext catalogPhotoViewerContext(int productId) => FormDraftContext(
  formType: 'catalog-photo-viewer',
  mode: FormDraftMode.action,
  productId: productId.toString(),
);

FormDraftContext catalogPhotoTagEditContext(int productId, int photoId) =>
    FormDraftContext(
      formType: 'catalog-photo-tags',
      mode: FormDraftMode.edit,
      entityId: photoId.toString(),
      productId: productId.toString(),
    );

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
  CatalogPhotoViewerNotifier(this.context);

  final FormDraftContext context;

  @override
  CatalogPhotoViewerState build() {
    ref.watch(formDraftSessionEpochProvider);
    return const CatalogPhotoViewerState();
  }

  void setCurrentIndex(int index) =>
      state = state.copyWith(currentIndex: index);

  void setDownloading(bool value) => state = state.copyWith(downloading: value);

  void setSharing(bool value) => state = state.copyWith(sharing: value);

  void reset(int initialIndex) =>
      state = CatalogPhotoViewerState(currentIndex: initialIndex);
}

/// Provider for the catalog photo viewer state.
final catalogPhotoViewerProvider =
    NotifierProvider.family<
      CatalogPhotoViewerNotifier,
      CatalogPhotoViewerState,
      FormDraftContext
    >(CatalogPhotoViewerNotifier.new);

/// State for the edit-caption bottom sheet (DG-404 Phase 4.7 / FR2).
///
/// Owns the `selectedTags` set and `saving` flag previously held as
/// `setState` fields inside `_EditCaptionSheetState`.
class CatalogEditCaptionState {
  const CatalogEditCaptionState({
    this.caption = '',
    this.selectedTags = const <String>{},
    this.saving = false,
  });

  final String caption;
  final Set<String> selectedTags;
  final bool saving;

  CatalogEditCaptionState copyWith({
    String? caption,
    Set<String>? selectedTags,
    bool? saving,
  }) {
    return CatalogEditCaptionState(
      caption: caption ?? this.caption,
      selectedTags: selectedTags ?? this.selectedTags,
      saving: saving ?? this.saving,
    );
  }
}

/// `Notifier` that owns the edit-caption sheet state (DG-404 Phase 4.7).
class CatalogEditCaptionNotifier extends Notifier<CatalogEditCaptionState> {
  CatalogEditCaptionNotifier(this.context);

  final FormDraftContext context;
  CatalogEditCaptionState _seededState = const CatalogEditCaptionState();

  @override
  CatalogEditCaptionState build() {
    ref.watch(formDraftSessionEpochProvider);
    final drafts = ref.read(formDraftSessionProvider);
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = _seededState;
      }
    });
    return drafts[context] as CatalogEditCaptionState? ?? _seededState;
  }

  bool get hasRetainedDraft =>
      ref.read(formDraftSessionProvider).containsKey(context);

  /// Seed the initial selected tags from the photo's existing tags.
  void seed(CatalogPhoto photo) {
    if (ref.read(formDraftSessionProvider).containsKey(context)) return;
    if (photo.tags.isEmpty) {
      _seededState = CatalogEditCaptionState(caption: photo.caption);
      state = _seededState;
      return;
    }
    final tags = <String>{};
    tags.addAll(
      photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
    );
    _seededState = CatalogEditCaptionState(
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

  void _retain(CatalogEditCaptionState next) {
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
    state = const CatalogEditCaptionState();
  }
}

/// Provider for the edit-caption sheet state.
final catalogEditCaptionProvider =
    NotifierProvider.family<
      CatalogEditCaptionNotifier,
      CatalogEditCaptionState,
      FormDraftContext
    >(CatalogEditCaptionNotifier.new);
