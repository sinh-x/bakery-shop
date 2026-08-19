import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the product catalog screen (DG-404 Phase 4.7 / FR2).
///
/// Owns the `showInactiveProducts` toggle previously held as a
/// `setState` field inside `_ProductCatalogScreenState`.
class ProductCatalogScreenState {
  const ProductCatalogScreenState({this.showInactiveProducts = false});

  final bool showInactiveProducts;

  ProductCatalogScreenState copyWith({bool? showInactiveProducts}) {
    return ProductCatalogScreenState(
      showInactiveProducts:
          showInactiveProducts ?? this.showInactiveProducts,
    );
  }
}

/// `Notifier` that owns the product catalog screen state
/// (DG-404 Phase 4.7 / FR2).
class ProductCatalogScreenNotifier
    extends Notifier<ProductCatalogScreenState> {
  @override
  ProductCatalogScreenState build() => const ProductCatalogScreenState();

  void setShowInactiveProducts(bool value) =>
      state = state.copyWith(showInactiveProducts: value);
}

/// Provider for the product catalog screen state.
final productCatalogScreenProvider =
    NotifierProvider<ProductCatalogScreenNotifier, ProductCatalogScreenState>(
        ProductCatalogScreenNotifier.new);