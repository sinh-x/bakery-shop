import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/date_formatting.dart';

/// Sync state for the Today Sales screen (DG-404 Phase 4.7 / FR2).
///
/// Owns the selected date for the Ngày tab, the week anchor for the
/// Tuần tab, and the month anchor for the Tháng tab — previously held
/// as `setState` fields inside `_TodaySalesScreenState`. Also owns a
/// `tabRebuildTick` counter that drives the AppBar title / calendar
/// action rebuild when the user switches tabs (the pre-migration
/// `_tabController.addListener` issued an empty `setState(() {})`).
///
/// The widget reads [todaySalesScreenProvider] and invokes the
/// notifier's mutators; no `setState` is required. The `TabController`
/// lifecycle itself (creation/dispose/listener wiring) stays on the
/// widget as acceptable-use per DG-404 guardrails.
class TodaySalesScreenState {
  const TodaySalesScreenState({
    required this.selectedDate,
    required this.weekAnchor,
    required this.monthAnchor,
    this.tabRebuildTick = 0,
  });

  final String selectedDate;
  final String weekAnchor;
  final String monthAnchor;
  final int tabRebuildTick;

  TodaySalesScreenState copyWith({
    String? selectedDate,
    String? weekAnchor,
    String? monthAnchor,
    int? tabRebuildTick,
  }) {
    return TodaySalesScreenState(
      selectedDate: selectedDate ?? this.selectedDate,
      weekAnchor: weekAnchor ?? this.weekAnchor,
      monthAnchor: monthAnchor ?? this.monthAnchor,
      tabRebuildTick: tabRebuildTick ?? this.tabRebuildTick,
    );
  }
}

TodaySalesScreenState _initialState() {
  final today = formatApiDate(DateTime.now());
  return TodaySalesScreenState(
    selectedDate: today,
    weekAnchor: today,
    monthAnchor: today,
  );
}

/// `Notifier` that owns the Today Sales screen state (DG-404 Phase
/// 4.7 / FR2). Sync state because all mutations are local.
class TodaySalesScreenNotifier extends Notifier<TodaySalesScreenState> {
  @override
  TodaySalesScreenState build() => _initialState();

  void setSelectedDate(String date) =>
      state = state.copyWith(selectedDate: date);

  void setWeekAnchor(String anchor) =>
      state = state.copyWith(weekAnchor: anchor);

  void setMonthAnchor(String anchor) =>
      state = state.copyWith(monthAnchor: anchor);

  /// Bump the rebuild counter so the widget re-reads the
  /// tab-controller-derived AppBar title / calendar action when the
  /// user switches tabs. Replaces the pre-migration empty
  /// `setState(() {})` driven by `_tabController.addListener`.
  void bumpTabRebuild() =>
      state = state.copyWith(tabRebuildTick: state.tabRebuildTick + 1);
}

/// Provider for the Today Sales screen state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final todaySalesScreenProvider =
    NotifierProvider<TodaySalesScreenNotifier, TodaySalesScreenState>(
        TodaySalesScreenNotifier.new);