import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expansion state for a single reconciliation history line card
/// (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_isExpanded` and `_saleRowsExpanded` toggles previously
/// mutated via `setState` inside `_ReconciliationHistoryLineCardState`.
/// The widget reads [reconciliationHistoryLineCardProvider] and invokes
/// the notifier's mutators; no `setState` is required.
class ReconciliationHistoryLineCardState {
  const ReconciliationHistoryLineCardState({
    this.isExpanded = false,
    this.saleRowsExpanded = false,
  });

  final bool isExpanded;
  final bool saleRowsExpanded;

  ReconciliationHistoryLineCardState copyWith({
    bool? isExpanded,
    bool? saleRowsExpanded,
  }) {
    return ReconciliationHistoryLineCardState(
      isExpanded: isExpanded ?? this.isExpanded,
      saleRowsExpanded: saleRowsExpanded ?? this.saleRowsExpanded,
    );
  }
}

/// `Notifier` that owns the expansion state for a single
/// reconciliation history line card (DG-404 Phase 4.7 / FR2). Keyed by
/// the history line id via a family provider so each card in the list
/// maintains its own expansion state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `ExpenseHistoryPhotoNotifier`).
class ReconciliationHistoryLineCardNotifier
    extends Notifier<ReconciliationHistoryLineCardState> {
  final int lineId;

  ReconciliationHistoryLineCardNotifier(this.lineId);

  @override
  ReconciliationHistoryLineCardState build() =>
      const ReconciliationHistoryLineCardState();

  void toggleExpanded() =>
      state = state.copyWith(isExpanded: !state.isExpanded);

  void toggleSaleRowsExpanded() =>
      state = state.copyWith(saleRowsExpanded: !state.saleRowsExpanded);
}

/// Family provider for the history line card expansion state, keyed by
/// the history line id.
final reconciliationHistoryLineCardProvider = NotifierProvider.family<
    ReconciliationHistoryLineCardNotifier,
    ReconciliationHistoryLineCardState,
    int>(ReconciliationHistoryLineCardNotifier.new);