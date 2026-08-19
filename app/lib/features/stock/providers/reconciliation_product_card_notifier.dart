import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expansion state for a single reconciliation product card
/// (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_isExpanded` toggle and the `_expandedOptionKeys` set
/// previously mutated via `setState` inside
/// `_ReconciliationProductCardState`. The counted-qty
/// `TextEditingController`s stay on the widget because
/// `TextEditingController` lifecycle is an acceptable-use case (see
/// DG-404 guardrails). The widget reads
/// [reconciliationProductCardProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class ReconciliationProductCardState {
  const ReconciliationProductCardState({
    this.isExpanded = false,
    this.expandedOptionKeys = const <String>{},
  });

  final bool isExpanded;
  final Set<String> expandedOptionKeys;

  ReconciliationProductCardState copyWith({
    bool? isExpanded,
    Set<String>? expandedOptionKeys,
  }) {
    return ReconciliationProductCardState(
      isExpanded: isExpanded ?? this.isExpanded,
      expandedOptionKeys: expandedOptionKeys ?? this.expandedOptionKeys,
    );
  }
}

/// `Notifier` that owns the expansion state for a single
/// reconciliation product card (DG-404 Phase 4.7 / FR2). Keyed by the
/// product id via a family provider so each card in the list maintains
/// its own expansion state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `ExpenseHistoryPhotoNotifier`).
class ReconciliationProductCardNotifier
    extends Notifier<ReconciliationProductCardState> {
  final int productId;

  ReconciliationProductCardNotifier(this.productId);

  @override
  ReconciliationProductCardState build() =>
      const ReconciliationProductCardState();

  void toggleExpanded() =>
      state = state.copyWith(isExpanded: !state.isExpanded);

  void toggleOption(String optionKey) {
    final next = Set<String>.from(state.expandedOptionKeys);
    if (next.contains(optionKey)) {
      next.remove(optionKey);
    } else {
      next.add(optionKey);
    }
    state = state.copyWith(expandedOptionKeys: next);
  }
}

/// Family provider for the product card expansion state, keyed by the
/// product id.
final reconciliationProductCardProvider = NotifierProvider.family<
    ReconciliationProductCardNotifier,
    ReconciliationProductCardState,
    int>(ReconciliationProductCardNotifier.new);