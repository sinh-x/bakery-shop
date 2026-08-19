import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';

/// Filter mode for [CustomerSearchFieldState]. Mirrors the private enum
/// previously held inside `_CustomerSearchFieldState` (DG-404 Phase 4.7).
enum CustomerSearchFilterMode { client, server }

/// State for the customer search field (DG-404 Phase 4.7).
///
/// Owns every field previously mutated via `setState` inside
/// `_CustomerSearchFieldState`: the loaded `allCustomers` list, the
/// browsable `listCustomers` slice, the client/server filter mode, the
/// loading flag, the selected customer, the focus-clear latch, the error
/// message, and the refine-hint flag. The widget reads
/// [customerSearchFieldProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class CustomerSearchFieldState {
  const CustomerSearchFieldState({
    this.allCustomers = const <Customer>[],
    this.listCustomers = const <Customer>[],
    this.mode = CustomerSearchFilterMode.client,
    this.loading = false,
    this.selected,
    this.clearedOnFocus = false,
    this.error,
    this.showRefineHint = false,
  });

  final List<Customer> allCustomers;
  final List<Customer> listCustomers;
  final CustomerSearchFilterMode mode;
  final bool loading;
  final Customer? selected;
  final bool clearedOnFocus;
  final String? error;
  final bool showRefineHint;

  CustomerSearchFieldState copyWith({
    List<Customer>? allCustomers,
    List<Customer>? listCustomers,
    CustomerSearchFilterMode? mode,
    bool? loading,
    Customer? selected,
    bool? clearedOnFocus,
    String? error,
    bool? showRefineHint,
  }) {
    return CustomerSearchFieldState(
      allCustomers: allCustomers ?? this.allCustomers,
      listCustomers: listCustomers ?? this.listCustomers,
      mode: mode ?? this.mode,
      loading: loading ?? this.loading,
      selected: selected ?? this.selected,
      clearedOnFocus: clearedOnFocus ?? this.clearedOnFocus,
      error: error ?? this.error,
      showRefineHint: showRefineHint ?? this.showRefineHint,
    );
  }
}

/// `Notifier` that owns the customer-search-field state
/// (DG-404 Phase 4.7). All mutations that previously lived in `setState`
/// closures inside `_CustomerSearchFieldState` are now exposed as notifier
/// methods. The widget reads the state via [customerSearchFieldProvider]
/// and rebuilds on change — no `setState` is required.
class CustomerSearchFieldNotifier extends Notifier<CustomerSearchFieldState> {
  /// Cap applied to the browse list and to server-side search results.
  static const int cap = 20;

  @override
  CustomerSearchFieldState build() => const CustomerSearchFieldState();

  void setInitialSelected(Customer? customer) =>
      state = state.copyWith(selected: customer);

  void markClearedOnFocus() =>
      state = state.copyWith(clearedOnFocus: true, selected: null);

  void startLoad() => state = state.copyWith(
        loading: true,
        error: null,
        showRefineHint: false,
      );

  void setLoadedAll(List<Customer> customers) {
    final mode = customers.length <= cap
        ? CustomerSearchFilterMode.client
        : CustomerSearchFilterMode.server;
    state = state.copyWith(
      allCustomers: customers,
      mode: mode,
      listCustomers: _browseList(customers),
      loading: false,
    );
  }

  void setLoadError(String message) => state = state.copyWith(
        loading: false,
        error: message,
      );

  /// Reset to the browse list (empty query). Mirrors the original
  /// `_applyBrowseList` + clear-error behaviour.
  void applyBrowseListForEmptyQuery() => state = state.copyWith(
        listCustomers: _browseList(state.allCustomers),
        error: null,
        showRefineHint: false,
      );

  /// Client-mode filter against the in-memory `allCustomers` list.
  void applyClientFilter(List<Customer> filtered) => state = state.copyWith(
        showRefineHint: false,
        listCustomers: filtered,
        error: null,
      );

  void startServerSearch() => state = state.copyWith(
        loading: true,
        error: null,
      );

  /// Set server-search results with an explicit refine-hint flag derived
  /// from the un-capped result count.
  void setServerResultsWithHint(List<Customer> capped, bool refine) =>
      state = state.copyWith(
        listCustomers: capped,
        showRefineHint: refine,
        loading: false,
      );

  void setServerError(String message) => state = state.copyWith(
        listCustomers: const [],
        loading: false,
        error: message,
        showRefineHint: false,
      );

  void select(Customer customer) => state = state.copyWith(
        selected: customer,
        error: null,
      );

  /// Compute the browse slice from a full customer list, matching the
  /// original `_applyBrowseList` behaviour.
  List<Customer> _browseList(List<Customer> all) {
    if (all.length <= cap) {
      return List<Customer>.from(all);
    }
    final sorted = List<Customer>.from(all)
      ..sort((a, b) => b.id.compareTo(a.id));
    return sorted.take(cap).toList();
  }
}

/// Provider for the customer-search-field state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final customerSearchFieldProvider =
    NotifierProvider<CustomerSearchFieldNotifier, CustomerSearchFieldState>(
  CustomerSearchFieldNotifier.new,
);