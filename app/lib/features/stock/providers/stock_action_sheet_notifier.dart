import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form state for the stock-action bottom sheet (DG-404 Phase 4.7 /
/// FR2).
///
/// Holds the `_isLoading` flag and `_selectedNormalizedPrice` value
/// previously mutated via `setState` inside `_StockActionSheetState`.
/// The quantity / reason / note `TextEditingController`s stay on the
/// widget because `TextEditingController` lifecycle is an
/// acceptable-use case (see DG-404 guardrails). The widget reads
/// [stockActionSheetProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class StockActionSheetState {
  const StockActionSheetState({
    this.isLoading = false,
    this.selectedNormalizedPrice,
  });

  final bool isLoading;
  final int? selectedNormalizedPrice;

  StockActionSheetState copyWith({
    bool? isLoading,
    int? selectedNormalizedPrice,
  }) {
    return StockActionSheetState(
      isLoading: isLoading ?? this.isLoading,
      selectedNormalizedPrice:
          selectedNormalizedPrice ?? this.selectedNormalizedPrice,
    );
  }
}

/// `Notifier` that owns the stock-action-sheet state (DG-404 Phase 4.7
/// / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_StockActionSheetState` are now exposed as notifier methods. The
/// widget reads the state via [stockActionSheetProvider] and rebuilds
/// on change — no `setState` is required.
class StockActionSheetNotifier extends Notifier<StockActionSheetState> {
  @override
  StockActionSheetState build() => const StockActionSheetState();

  /// Seed the initial normalized price selection from the item's
  /// per-chip list and the optional pre-selected price. Called once
  /// from `initState`.
  void seedSelectedNormalizedPrice(int? price) =>
      state = state.copyWith(selectedNormalizedPrice: price);

  void setSelectedNormalizedPrice(int? value) =>
      state = state.copyWith(selectedNormalizedPrice: value);

  void setLoading(bool value) =>
      state = state.copyWith(isLoading: value);
}

/// Provider for the stock-action-sheet state. The sheet reads this and
/// calls the notifier's mutators; no `setState` is required.
final stockActionSheetProvider =
    NotifierProvider<StockActionSheetNotifier, StockActionSheetState>(
        StockActionSheetNotifier.new);