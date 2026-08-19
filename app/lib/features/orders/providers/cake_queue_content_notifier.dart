import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/date_filter_chips.dart';

/// Cake-queue content filter/collapse state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_includeReady`, `_selectedDateFilter`, and `_collapsedGroups`
/// fields previously mutated via `setState` inside `_CakeQueueContentState`.
/// The widget reads [cakeQueueContentProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class CakeQueueContentState {
  const CakeQueueContentState({
    this.includeReady = false,
    this.selectedDateFilter = DateFilterOption.all,
    this.collapsedGroups = const <String, bool>{},
  });

  final bool includeReady;
  final DateFilterOption selectedDateFilter;
  final Map<String, bool> collapsedGroups;

  CakeQueueContentState copyWith({
    bool? includeReady,
    DateFilterOption? selectedDateFilter,
    Map<String, bool>? collapsedGroups,
    bool clearCollapsedGroups = false,
  }) =>
      CakeQueueContentState(
        includeReady: includeReady ?? this.includeReady,
        selectedDateFilter: selectedDateFilter ?? this.selectedDateFilter,
        collapsedGroups: clearCollapsedGroups
            ? const <String, bool>{}
            : (collapsedGroups ?? this.collapsedGroups),
      );
}

class CakeQueueContentNotifier extends Notifier<CakeQueueContentState> {
  @override
  CakeQueueContentState build() => const CakeQueueContentState();

  void setDateFilter(DateFilterOption option) =>
      state = state.copyWith(selectedDateFilter: option, clearCollapsedGroups: true);

  void setIncludeReady(bool value) =>
      state = state.copyWith(includeReady: value, clearCollapsedGroups: true);

  void toggleGroupCollapse(String status) {
    final next = Map<String, bool>.from(state.collapsedGroups);
    final current = next[status] ?? false;
    next[status] = !current;
    state = state.copyWith(collapsedGroups: next);
  }
}

final cakeQueueContentProvider =
    NotifierProvider<CakeQueueContentNotifier, CakeQueueContentState>(
        CakeQueueContentNotifier.new);