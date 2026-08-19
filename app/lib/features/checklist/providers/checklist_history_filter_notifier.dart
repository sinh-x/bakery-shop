import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sync state for the checklist history screen (DG-404 Phase 4.7).
///
/// Owns the date-range filter (`_fromDate` / `_toDate`) previously held
/// as `setState` fields inside `_ChecklistHistoryScreenState`. The widget
/// reads [checklistHistoryFilterProvider] and invokes the notifier's
/// mutators; the notifier emits new state and the widget rebuilds via
/// `ref.watch`. No `setState` is required.
class ChecklistHistoryFilterState {
  const ChecklistHistoryFilterState({
    required this.fromDate,
    required this.toDate,
  });

  final DateTime fromDate;
  final DateTime toDate;

  ChecklistHistoryFilterState copyWith({
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return ChecklistHistoryFilterState(
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
    );
  }
}

/// Initial date range used when the checklist history screen first builds
/// (today and the 6 preceding days — matches the pre-migration
/// `_ChecklistHistoryScreenState` `initState` default).
ChecklistHistoryFilterState _initialFilterState() {
  final today = DateTime.now();
  return ChecklistHistoryFilterState(
    toDate: today,
    fromDate: today.subtract(const Duration(days: 6)),
  );
}

/// `Notifier` that owns the checklist-history date-range filter state
/// (DG-404 Phase 4.7). Sync state because all mutations are local; the
/// actual history fetch is driven by the widget reading the current
/// range and calling the history provider.
class ChecklistHistoryFilterNotifier
    extends Notifier<ChecklistHistoryFilterState> {
  @override
  ChecklistHistoryFilterState build() => _initialFilterState();

  void setFromDate(DateTime value) =>
      state = state.copyWith(fromDate: value);

  void setToDate(DateTime value) =>
      state = state.copyWith(toDate: value);
}

/// Provider for the checklist-history date-range filter state. The widget
/// reads this and calls the notifier's mutators; no `setState` is required.
final checklistHistoryFilterProvider =
    NotifierProvider<ChecklistHistoryFilterNotifier,
        ChecklistHistoryFilterState>(ChecklistHistoryFilterNotifier.new);