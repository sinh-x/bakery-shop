import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the knowledge photo gallery strip and full-screen viewer
/// (DG-404 Phase 4.7 / FR2).
///
/// Owns the current page index and the sharing flag previously held as
/// `setState` fields inside `_KnowledgePhotoGalleryState` and
/// `_FullScreenViewerState`.
class KnowledgePhotoGalleryState {
  const KnowledgePhotoGalleryState({
    this.currentIndex = 0,
    this.sharing = false,
  });

  final int currentIndex;
  final bool sharing;

  KnowledgePhotoGalleryState copyWith({
    int? currentIndex,
    bool? sharing,
  }) {
    return KnowledgePhotoGalleryState(
      currentIndex: currentIndex ?? this.currentIndex,
      sharing: sharing ?? this.sharing,
    );
  }
}

/// `Notifier` that owns the photo-gallery strip state (DG-404 Phase 4.7 /
/// FR2). The widget reads [knowledgePhotoGalleryProvider] and invokes
/// mutators; no `setState` is required.
class KnowledgePhotoGalleryNotifier
    extends Notifier<KnowledgePhotoGalleryState> {
  @override
  KnowledgePhotoGalleryState build() => const KnowledgePhotoGalleryState();

  void setCurrentIndex(int index) =>
      state = state.copyWith(currentIndex: index);

  void setSharing(bool value) => state = state.copyWith(sharing: value);
}

/// Provider for the photo-gallery strip state.
final knowledgePhotoGalleryProvider =
    NotifierProvider<KnowledgePhotoGalleryNotifier,
        KnowledgePhotoGalleryState>(KnowledgePhotoGalleryNotifier.new);

/// `Notifier` that owns the full-screen photo viewer state (DG-404 Phase
/// 4.7 / FR2). Keyed by the initial index via a family provider so each
/// viewer instance maintains its own state.
class KnowledgeFullScreenPhotoNotifier
    extends Notifier<KnowledgePhotoGalleryState> {
  final int initialIndex;

  KnowledgeFullScreenPhotoNotifier(this.initialIndex);

  @override
  KnowledgePhotoGalleryState build() =>
      KnowledgePhotoGalleryState(currentIndex: initialIndex);

  void setCurrentIndex(int index) =>
      state = state.copyWith(currentIndex: index);

  void setSharing(bool value) => state = state.copyWith(sharing: value);
}

/// Family provider for the full-screen photo viewer state, keyed by the
/// initial page index.
final knowledgeFullScreenPhotoProvider =
    NotifierProvider.family<KnowledgeFullScreenPhotoNotifier,
        KnowledgePhotoGalleryState, int>(
    KnowledgeFullScreenPhotoNotifier.new);