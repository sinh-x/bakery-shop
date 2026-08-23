import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Order work-item section state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_expanded` and `_transitioning` fields previously mutated via
/// `setState` inside `_OrderWorkItemSectionState`. The widget reads
/// [orderWorkItemSectionProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderWorkItemSectionState {
  const OrderWorkItemSectionState({
    this.expanded = true,
    this.transitioning = false,
  });

  final bool expanded;
  final bool transitioning;

  OrderWorkItemSectionState copyWith({
    bool? expanded,
    bool? transitioning,
  }) =>
      OrderWorkItemSectionState(
        expanded: expanded ?? this.expanded,
        transitioning: transitioning ?? this.transitioning,
      );
}

class OrderWorkItemSectionNotifier extends Notifier<OrderWorkItemSectionState> {
  @override
  OrderWorkItemSectionState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderWorkItemSectionState(),
    );
    return const OrderWorkItemSectionState();
  }

  void toggleExpanded() =>
      state = state.copyWith(expanded: !state.expanded);

  void setTransitioning(bool value) =>
      state = state.copyWith(transitioning: value);
}

final orderWorkItemSectionProvider =
    NotifierProvider<OrderWorkItemSectionNotifier, OrderWorkItemSectionState>(
        OrderWorkItemSectionNotifier.new);
