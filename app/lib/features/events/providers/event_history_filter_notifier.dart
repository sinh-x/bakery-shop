import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Internal enum mirror for the event history list date-range filter.
///
/// The original `_DateRange` enum in `event_history_list.dart` was
/// private to the widget; the notifier mirrors it here so it can own
/// the value without a circular import. The widget maps between its
/// private enum and this public one.
enum EventHistoryDateRange { today, week, month, all }

/// State for the event-history list filter bar (DG-404 Phase 4.2 / FR2).
///
/// Owns the active date-range filter, type filter, and search-expanded
/// flag previously held as `setState` fields inside
/// `_EventHistoryListState`. The search text itself remains in a
/// `TextEditingController` owned by the widget (text-controller
/// listener case — acceptable use, see §4).
class EventHistoryFilterState {
  const EventHistoryFilterState({
    this.dateRange = EventHistoryDateRange.today,
    this.typeFilter,
    this.searchExpanded = false,
  });

  final EventHistoryDateRange dateRange;
  final String? typeFilter;
  final bool searchExpanded;

  EventHistoryFilterState copyWith({
    EventHistoryDateRange? dateRange,
    String? typeFilter,
    bool? searchExpanded,
    bool clearTypeFilter = false,
  }) {
    return EventHistoryFilterState(
      dateRange: dateRange ?? this.dateRange,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      searchExpanded: searchExpanded ?? this.searchExpanded,
    );
  }
}

/// `Notifier` that owns the event-history filter state (DG-404 Phase
/// 4.2 / FR2). The widget reads [eventHistoryFilterProvider] and
/// invokes mutators; no `setState` is required.
class EventHistoryFilterNotifier
    extends Notifier<EventHistoryFilterState> {
  @override
  EventHistoryFilterState build() => const EventHistoryFilterState();

  void setDateRange(EventHistoryDateRange value) =>
      state = state.copyWith(dateRange: value);

  void setTypeFilter(String? value) =>
      state = state.copyWith(typeFilter: value);

  void setSearchExpanded(bool value) =>
      state = state.copyWith(searchExpanded: value);

  void collapseSearch() =>
      state = state.copyWith(searchExpanded: false);
}

/// Provider for the event-history filter state.
final eventHistoryFilterProvider =
    NotifierProvider<EventHistoryFilterNotifier, EventHistoryFilterState>(
  EventHistoryFilterNotifier.new,
);