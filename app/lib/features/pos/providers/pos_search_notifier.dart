import 'package:flutter_riverpod/flutter_riverpod.dart';

/// POS product-grid filter state for the POS home screen
/// (DG-404 Phase 4.5 / FR2).
///
/// Owns the `_searchQuery`, `_showOutOfStockProducts`, and
/// `_lastStockRefreshAt` fields previously mutated via `setState` inside
/// `_PosScreenState`. The widget reads [posSearchProvider] /
/// [posStockVisibilityProvider] / [posStockRefreshProvider] and invokes the
/// notifier mutators; no `setState` is required.
class PosSearchState {
  const PosSearchState({
    this.searchQuery = '',
    this.showOutOfStockProducts = false,
    this.lastStockRefreshAt,
  });

  final String searchQuery;
  final bool showOutOfStockProducts;
  final DateTime? lastStockRefreshAt;

  PosSearchState copyWith({
    String? searchQuery,
    bool? showOutOfStockProducts,
    DateTime? lastStockRefreshAt,
  }) =>
      PosSearchState(
        searchQuery: searchQuery ?? this.searchQuery,
        showOutOfStockProducts:
            showOutOfStockProducts ?? this.showOutOfStockProducts,
        lastStockRefreshAt: lastStockRefreshAt ?? this.lastStockRefreshAt,
      );
}

/// `Notifier` that owns the POS home-screen filter state (DG-404 Phase 4.5
/// / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_PosScreenState` are now exposed as notifier methods. The widget reads
/// the state via [posSearchProvider] and rebuilds on change — no
/// `setState` is required.
class PosSearchNotifier extends Notifier<PosSearchState> {
  @override
  PosSearchState build() => PosSearchState(
        lastStockRefreshAt: DateTime.now(),
      );

  /// Update the search query (empty string clears the search).
  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  /// Toggle whether out-of-stock products are visible.
  void setShowOutOfStockProducts(bool value) =>
      state = state.copyWith(showOutOfStockProducts: value);

  /// Record that a manual stock refresh just happened.
  void markStockRefreshed() =>
      state = state.copyWith(lastStockRefreshAt: DateTime.now());
}

/// Provider for the POS home-screen filter state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final posSearchProvider =
    NotifierProvider<PosSearchNotifier, PosSearchState>(PosSearchNotifier.new);