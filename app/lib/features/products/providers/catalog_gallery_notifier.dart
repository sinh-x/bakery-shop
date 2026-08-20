import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the catalog gallery section (DG-404 Phase 4.7 / FR2).
///
/// Owns the `promoting` flag previously held as a `setState` field
/// inside `_CatalogGallerySectionState`.
class CatalogGalleryState {
  const CatalogGalleryState({this.promoting = false});

  final bool promoting;

  CatalogGalleryState copyWith({bool? promoting}) {
    return CatalogGalleryState(promoting: promoting ?? this.promoting);
  }
}

/// `Notifier` that owns the catalog gallery section state
/// (DG-404 Phase 4.7). Keyed by the product id via a family provider so
/// each product form maintains its own gallery state.
class CatalogGalleryNotifier extends Notifier<CatalogGalleryState> {
  final int productId;

  CatalogGalleryNotifier(this.productId);

  @override
  CatalogGalleryState build() => const CatalogGalleryState();

  void setPromoting(bool value) =>
      state = state.copyWith(promoting: value);
}

/// Family provider for the catalog gallery section state, keyed by
/// product id.
final catalogGalleryProvider =
    NotifierProvider.family<CatalogGalleryNotifier, CatalogGalleryState, int>(
        CatalogGalleryNotifier.new);