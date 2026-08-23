import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/date_filter_chips.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Filtered-orders screen search-query state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_searchQuery` field previously mutated via `setState` inside
/// `_FilteredOrdersScreenState`. The widget reads
/// [filteredOrdersSearchProvider] and invokes the notifier's
/// [setQuery]/[clearQuery] methods; no `setState` is required.
class FilteredOrdersSearchNotifier extends Notifier<String> {
  @override
  String build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = '');
    return '';
  }

  void setQuery(String value) => state = value;

  void clearQuery() => state = '';
}

final filteredOrdersSearchProvider =
    NotifierProvider<FilteredOrdersSearchNotifier, String>(
        FilteredOrdersSearchNotifier.new);

/// Order-history screen search + date-filter-mode state (DG-404 Phase 4.6 /
/// FR2).
///
/// Owns the `_searchQuery`, `_mode`, and `_rangeError` fields previously
/// mutated via `setState` inside `_OrderHistoryScreenState`. The widget
/// reads [orderHistoryFilterProvider] and invokes the notifier's mutators;
/// no `setState` is required.
enum OrderHistoryDateFilterMode { single, range }

class OrderHistoryFilterState {
  const OrderHistoryFilterState({
    this.searchQuery = '',
    this.mode = OrderHistoryDateFilterMode.range,
    this.rangeError,
  });

  final String searchQuery;
  final OrderHistoryDateFilterMode mode;
  final String? rangeError;

  OrderHistoryFilterState copyWith({
    String? searchQuery,
    OrderHistoryDateFilterMode? mode,
    String? rangeError,
    bool clearRangeError = false,
  }) =>
      OrderHistoryFilterState(
        searchQuery: searchQuery ?? this.searchQuery,
        mode: mode ?? this.mode,
        rangeError:
            clearRangeError ? null : (rangeError ?? this.rangeError),
      );
}

class OrderHistoryFilterNotifier extends Notifier<OrderHistoryFilterState> {
  @override
  OrderHistoryFilterState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderHistoryFilterState(),
    );
    return const OrderHistoryFilterState();
  }

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  void clearSearchQuery() => state = state.copyWith(searchQuery: '');

  void setMode(OrderHistoryDateFilterMode mode) =>
      state = state.copyWith(mode: mode);

  void setSingleMode() => state = state.copyWith(
        mode: OrderHistoryDateFilterMode.single,
        clearRangeError: true,
      );

  void setRangeModeWithError(String? error) => state = state.copyWith(
        mode: OrderHistoryDateFilterMode.range,
        rangeError: error,
      );

  void setRangeModeSuccess() => state = state.copyWith(
        mode: OrderHistoryDateFilterMode.range,
        clearRangeError: true,
      );
}

final orderHistoryFilterProvider =
    NotifierProvider<OrderHistoryFilterNotifier, OrderHistoryFilterState>(
        OrderHistoryFilterNotifier.new);

/// Order-list screen filter state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_statusFilter`, `_searchQuery`, `_viewMode`, `_dateFilter`,
/// and the tab-index-driven rebuild fields previously mutated via
/// `setState` inside `_OrderListScreenState`. The widget reads
/// [orderListFilterProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderListFilterState {
  const OrderListFilterState({
    this.statusFilter = 'new',
    this.searchQuery = '',
    this.viewMode = 'list',
    this.dateFilter = DateFilterOption.all,
  });

  final String statusFilter;
  final String searchQuery;
  final String viewMode;
  final DateFilterOption dateFilter;

  OrderListFilterState copyWith({
    String? statusFilter,
    String? searchQuery,
    String? viewMode,
    DateFilterOption? dateFilter,
  }) =>
      OrderListFilterState(
        statusFilter: statusFilter ?? this.statusFilter,
        searchQuery: searchQuery ?? this.searchQuery,
        viewMode: viewMode ?? this.viewMode,
        dateFilter: dateFilter ?? this.dateFilter,
      );
}

class OrderListFilterNotifier extends Notifier<OrderListFilterState> {
  @override
  OrderListFilterState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderListFilterState(),
    );
    return const OrderListFilterState();
  }

  void setStatusFilter(String value) =>
      state = state.copyWith(statusFilter: value);

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  void clearSearchQuery() => state = state.copyWith(searchQuery: '');

  void setViewMode(String mode) => state = state.copyWith(viewMode: mode);

  void setDateFilter(DateFilterOption option) =>
      state = state.copyWith(dateFilter: option);
}

final orderListFilterProvider =
    NotifierProvider<OrderListFilterNotifier, OrderListFilterState>(
        OrderListFilterNotifier.new);

/// Rebuild trigger for the order-list screen's tab controller (DG-404
/// Phase 4.6). The list screen previously used
/// `_tabController.addListener(() => setState(() {}))` to rebuild the
/// AppBar title (urgency/incomplete badges visibility) when the user
/// switched tabs. This notifier replaces that empty `setState` with a
/// counter bump the title watches.
class OrderListTabRebuildNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = 0);
    return 0;
  }

  void bump() => state++;
}

final orderListTabRebuildProvider =
    NotifierProvider<OrderListTabRebuildNotifier, int>(
        OrderListTabRebuildNotifier.new);
