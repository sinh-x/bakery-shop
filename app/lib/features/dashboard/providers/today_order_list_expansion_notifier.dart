import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sync state for the today-order-list expansion (DG-404 Phase 4.7 /
/// FR2). Owns the per-status expand/collapse map and the set of
/// status keys that have already been seeded with an explicit state —
/// previously held as `setState` fields inside
/// `_TodayOrderListState` (the `_expansionController` +
/// `_seededStatuses` pair). All groups default to expanded so the
/// pre-Phase-10 behavior is preserved until the user taps a header.
class TodayOrderListExpansionState {
  const TodayOrderListExpansionState({
    this.expandedByStatus = const <String, bool>{},
    this.seededStatuses = const <String>{},
  });

  final Map<String, bool> expandedByStatus;
  final Set<String> seededStatuses;

  bool isExpanded(String status) => expandedByStatus[status] ?? false;
  bool isSeeded(String status) => seededStatuses.contains(status);

  TodayOrderListExpansionState copyWith({
    Map<String, bool>? expandedByStatus,
    Set<String>? seededStatuses,
  }) {
    return TodayOrderListExpansionState(
      expandedByStatus: expandedByStatus ?? this.expandedByStatus,
      seededStatuses: seededStatuses ?? this.seededStatuses,
    );
  }
}

/// `Notifier` that owns the today-order-list expansion state (DG-404
/// Phase 4.7 / FR2). Sync state because all mutations are local.
/// Replaces the pre-migration `CategorySectionExpansionController` +
/// `_seededStatuses` `setState` pair.
class TodayOrderListExpansionNotifier
    extends Notifier<TodayOrderListExpansionState> {
  @override
  TodayOrderListExpansionState build() =>
      const TodayOrderListExpansionState();

  /// Seed a status group as expanded (called from `initState` /
  /// `didUpdateWidget` for newly-appeared groups). Idempotent: a
  /// group that was already seeded keeps its user-toggled value.
  void seedExpanded(String status) {
    if (state.isSeeded(status)) return;
    final expanded = Map<String, bool>.from(state.expandedByStatus)
      ..[status] = true;
    final seeded = Set<String>.from(state.seededStatuses)..add(status);
    state = state.copyWith(
      expandedByStatus: expanded,
      seededStatuses: seeded,
    );
  }

  /// Toggle a status group's expand/collapse state and record the
  /// user's explicit choice so a later refresh does not re-seed it.
  void toggle(String status) {
    final expanded = Map<String, bool>.from(state.expandedByStatus)
      ..[status] = !state.isExpanded(status);
    final seeded = Set<String>.from(state.seededStatuses)..add(status);
    state = state.copyWith(
      expandedByStatus: expanded,
      seededStatuses: seeded,
    );
  }
}

/// Provider for the today-order-list expansion state.
final todayOrderListExpansionProvider =
    NotifierProvider<TodayOrderListExpansionNotifier,
        TodayOrderListExpansionState>(TodayOrderListExpansionNotifier.new);