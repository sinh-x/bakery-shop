import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../data/models/customer.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Inline customer-suggestions search state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_results`, `_loading`, `_searched`, `_error`, and
/// `_showRefineHint` fields previously mutated via `setState` inside
/// `_OrderCustomerSuggestionsState`. The widget reads
/// [orderCustomerSuggestionsProvider] and invokes the notifier's
/// [search]/[clear] methods; no `setState` is required.
class OrderCustomerSuggestionsState {
  const OrderCustomerSuggestionsState({
    this.results = const [],
    this.loading = false,
    this.searched = false,
    this.error,
    this.showRefineHint = false,
  });

  final List<Customer> results;
  final bool loading;
  final bool searched;
  final String? error;
  final bool showRefineHint;

  OrderCustomerSuggestionsState copyWith({
    List<Customer>? results,
    bool? loading,
    bool? searched,
    String? error,
    bool? showRefineHint,
    bool clearError = false,
  }) =>
      OrderCustomerSuggestionsState(
        results: results ?? this.results,
        loading: loading ?? this.loading,
        searched: searched ?? this.searched,
        error: clearError ? null : (error ?? this.error),
        showRefineHint: showRefineHint ?? this.showRefineHint,
      );
}

/// `AsyncNotifier`-style notifier (synchronous, owns mutable state) for the
/// inline order customer-suggestions search (DG-404 Phase 4.6 / FR2).
class OrderCustomerSuggestionsNotifier
    extends Notifier<OrderCustomerSuggestionsState> {
  int _generation = 0;

  @override
  OrderCustomerSuggestionsState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      _generation++;
      state = const OrderCustomerSuggestionsState();
    });
    return const OrderCustomerSuggestionsState();
  }

  /// Run a backend customer search for [query], capping results at
  /// [CustomersLabels.orderSuggestionsCap] rows and surfacing a refine hint
  /// when more were returned.
  Future<void> search(String query, CustomerService service) async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final results = await service.listCustomers(search: query);
      if (generation != _generation) return;
      const cap = CustomersLabels.orderSuggestionsCap;
      final capped = results.take(cap).toList();
      state = state.copyWith(
        results: capped,
        showRefineHint: results.length > cap,
        loading: false,
        searched: true,
      );
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('[OrderCustomerSuggestions] search failed: $e');
      state = state.copyWith(
        results: const [],
        loading: false,
        error: CustomersLabels.orderSuggestionsError,
        showRefineHint: false,
      );
    }
  }

  /// Reset the suggestions to the empty/Idle state.
  void clear() {
    _generation++;
    state = const OrderCustomerSuggestionsState();
  }
}

final orderCustomerSuggestionsProvider =
    NotifierProvider<OrderCustomerSuggestionsNotifier,
        OrderCustomerSuggestionsState>(OrderCustomerSuggestionsNotifier.new);
