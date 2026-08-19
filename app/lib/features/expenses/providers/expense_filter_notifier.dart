import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event.dart';
import '../widgets/expense_filter_card.dart';

/// Sync state for the expense history screen (DG-404 Phase 4.1).
///
/// Owns all expense filter fields previously held as local `setState`
/// fields inside `_ExpenseScreenState`: date range, date filter mode,
/// category/subcategory/payment source/paid-by/logged-by filters, debt
/// status filter, and the search query text (kept in sync with the
/// [TextEditingController] for back-reads). Also owns the history list
/// (`_history`), the initial-loading flag, and the deleting flag.
///
/// The widget reads [expenseFilterProvider] and invokes the notifier
/// methods to mutate state; the notifier emits new state and the widget
/// rebuilds via `ref.watch`. No `setState` is required.
class ExpenseFilterState {
  const ExpenseFilterState({
    this.since,
    this.until,
    this.dateFilterMode = ExpenseDateFilterMode.range,
    this.filterCategory = '',
    this.filterSubcategory = '',
    this.filterPaymentSource = '',
    this.filterPaidByName = '',
    this.filterLoggedByName = '',
    this.filterDebtStatus = ExpenseDebtStatusFilter.all,
    this.searchText = '',
    this.history = const <BakeryEvent>[],
    this.initialHistoryLoading = true,
    this.deleting = false,
  });

  final DateTime? since;
  final DateTime? until;
  final ExpenseDateFilterMode dateFilterMode;
  final String filterCategory;
  final String filterSubcategory;
  final String filterPaymentSource;
  final String filterPaidByName;
  final String filterLoggedByName;
  final ExpenseDebtStatusFilter filterDebtStatus;
  final String searchText;
  final List<BakeryEvent> history;
  final bool initialHistoryLoading;
  final bool deleting;

  ExpenseFilterState copyWith({
    DateTime? since,
    DateTime? until,
    ExpenseDateFilterMode? dateFilterMode,
    String? filterCategory,
    String? filterSubcategory,
    String? filterPaymentSource,
    String? filterPaidByName,
    String? filterLoggedByName,
    ExpenseDebtStatusFilter? filterDebtStatus,
    String? searchText,
    List<BakeryEvent>? history,
    bool? initialHistoryLoading,
    bool? deleting,
  }) {
    return ExpenseFilterState(
      since: since ?? this.since,
      until: until ?? this.until,
      dateFilterMode: dateFilterMode ?? this.dateFilterMode,
      filterCategory: filterCategory ?? this.filterCategory,
      filterSubcategory: filterSubcategory ?? this.filterSubcategory,
      filterPaymentSource: filterPaymentSource ?? this.filterPaymentSource,
      filterPaidByName: filterPaidByName ?? this.filterPaidByName,
      filterLoggedByName: filterLoggedByName ?? this.filterLoggedByName,
      filterDebtStatus: filterDebtStatus ?? this.filterDebtStatus,
      searchText: searchText ?? this.searchText,
      history: history ?? this.history,
      initialHistoryLoading:
          initialHistoryLoading ?? this.initialHistoryLoading,
      deleting: deleting ?? this.deleting,
    );
  }
}

/// Initial date range used when the expense screen first builds (today and
/// the 6 preceding days — matches the pre-migration `_ExpenseScreenState`
/// `initState` default).
ExpenseFilterState _initialFilterState() {
  final today = DateTime.now();
  final until = DateTime(today.year, today.month, today.day);
  final since = until.subtract(const Duration(days: 6));
  return ExpenseFilterState(since: since, until: until);
}

/// `Notifier` that owns the expense-screen filter + view state (DG-404
/// Phase 4.1 / FR2). Sync state because all mutations are local; the
/// actual history fetch is driven by the widget reading the current
/// filter values and calling its loader.
class ExpenseFilterNotifier extends Notifier<ExpenseFilterState> {
  @override
  ExpenseFilterState build() => _initialFilterState();

  void setDeleting(bool value) =>
      state = state.copyWith(deleting: value);

  void setHistory(List<BakeryEvent> events) => state = state.copyWith(
        history: events,
        initialHistoryLoading: false,
      );

  void setInitialHistoryLoading(bool value) =>
      state = state.copyWith(initialHistoryLoading: value);

  void setSearchText(String text) =>
      state = state.copyWith(searchText: text);

  void clearFilters() => state = ExpenseFilterState(
        since: null,
        until: null,
        dateFilterMode: ExpenseDateFilterMode.range,
        filterCategory: '',
        filterSubcategory: '',
        filterPaymentSource: '',
        filterPaidByName: '',
        filterLoggedByName: '',
        filterDebtStatus: ExpenseDebtStatusFilter.all,
        searchText: '',
        history: state.history,
        initialHistoryLoading: state.initialHistoryLoading,
        deleting: state.deleting,
      );

  void setDebtStatus(ExpenseDebtStatusFilter value) =>
      state = state.copyWith(filterDebtStatus: value);

  void setSubcategory(String value) =>
      state = state.copyWith(filterSubcategory: value);

  void setCategory(String value) => state = state.copyWith(
        filterCategory: value,
        filterSubcategory: '',
      );

  void setPaymentSource(String value) =>
      state = state.copyWith(filterPaymentSource: value);

  void setPaidByName(String value) =>
      state = state.copyWith(filterPaidByName: value);

  void setLoggedByName(String value) =>
      state = state.copyWith(filterLoggedByName: value);

  void setDateFilterMode(ExpenseDateFilterMode value) {
    var until = state.until;
    if (value == ExpenseDateFilterMode.single && state.since != null) {
      until = state.since;
    }
    state = state.copyWith(dateFilterMode: value, until: until);
  }

  /// Apply a single picked date (single-mode behaviour).
  void setSingleDate(DateTime picked) =>
      state = state.copyWith(since: picked, until: picked);

  /// Apply a picked date range (range-mode behaviour).
  void setDateRange(DateTime start, DateTime end) =>
      state = state.copyWith(since: start, until: end);
}

/// Provider for the expense-screen filter + view state. The widget reads
/// this and calls the notifier's mutators; no `setState` is required.
final expenseFilterProvider =
    NotifierProvider<ExpenseFilterNotifier, ExpenseFilterState>(
  ExpenseFilterNotifier.new,
);