import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/address_service.dart';
import '../../data/models/address.dart';

/// Minimum query length before autocomplete fires (matches the backend
/// `AUTOCOMPLETE_MIN_QUERY_LEN` in `src/baker/services/address_library.py`).
const kAddressAutocompleteMinQueryLen = 2;

/// Debounce window for autocomplete queries (FR1/AC1 — "within 300ms").
/// The backend p95 budget is covered by the v101 index on
/// `normalized_address`; this client-side debounce collapses rapid typing
/// so we only fire one network request per typing burst.
const kAddressAutocompleteDebounce = Duration(milliseconds: 300);

/// Input for the debounced autocomplete fetch (DG-385 Phase 4 / FR1).
///
/// Riverpod providers are keyed by equality, so this value-class lets the
/// [addressAutocompleteProvider] family rebuild only when the debounced
/// query or the selected customer actually changes. Empty [query] means
/// "no suggestions" — the provider short-circuits to an empty list.
class AddressAutocompleteRequest {
  const AddressAutocompleteRequest({
    required this.query,
    required this.customerId,
  });

  final String query;
  final int? customerId;

  @override
  bool operator ==(Object other) =>
      other is AddressAutocompleteRequest &&
      other.query == query &&
      other.customerId == customerId;

  @override
  int get hashCode => Object.hash(query, customerId);

  bool get isValid => query.trim().length >= kAddressAutocompleteMinQueryLen;
}

/// Notifier holding the current (debounced) autocomplete query and the
/// selected customer id (FR5/AC5). The UI calls [onQueryChanged] on every
/// keystroke; the notifier debounces for [kAddressAutocompleteDebounce]
/// before publishing the new [AddressAutocompleteRequest] so the
/// [addressAutocompleteProvider] family only fetches once per typing burst.
///
/// Holding both the raw query and the debounced request in the same notifier
/// keeps the riverpod graph small and makes the debounce lifecycle testable
/// without pumping real `Future.delayed` through the widget tree.
class AddressAutocompleteQueryNotifier
    extends Notifier<AddressAutocompleteRequest> {
  Timer? _debounce;

  @override
  AddressAutocompleteRequest build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const AddressAutocompleteRequest(query: '', customerId: null);
  }

  /// Update the raw query text. Debounces for
  /// [kAddressAutocompleteDebounce] before publishing the new request so
  /// the fetch provider only fires once per typing burst (FR1/AC1).
  void onQueryChanged(String query, {int? customerId}) {
    _debounce?.cancel();
    _debounce = Timer(kAddressAutocompleteDebounce, () {
      state = AddressAutocompleteRequest(query: query, customerId: customerId);
    });
  }

  /// Update the selected customer immediately (no debounce) — re-runs the
  /// fetch so the customer's addresses move to the top (FR5/AC5).
  void onCustomerChanged(int? customerId) {
    _debounce?.cancel();
    final current = state;
    state = AddressAutocompleteRequest(
      query: current.query,
      customerId: customerId,
    );
  }

  /// Clear the query and any in-flight debounce (e.g. when the user selects
  /// a suggestion or leaves the field).
  void clear() {
    _debounce?.cancel();
    state = const AddressAutocompleteRequest(query: '', customerId: null);
  }
}

final addressAutocompleteQueryProvider =
    NotifierProvider<AddressAutocompleteQueryNotifier, AddressAutocompleteRequest>(
  AddressAutocompleteQueryNotifier.new,
);

/// Debounced autocomplete suggestions (FR1/FR5/AC1/AC5).
///
/// A family keyed by [AddressAutocompleteRequest] so the fetch only re-runs
/// when the debounced query or the selected customer actually changes. The
/// UI should watch [addressAutocompleteQueryProvider] to drive the
/// debounce, then read this provider with the resulting request. Empty or
/// too-short queries short-circuit to an empty list without hitting the
/// backend (FR1 — "2+ characters").
final addressAutocompleteProvider =
    FutureProvider.family<List<AddressSuggestion>, AddressAutocompleteRequest>(
  (ref, request) async {
    if (!request.isValid) return const <AddressSuggestion>[];
    final service = ref.read(addressServiceProvider);
    try {
      return service.autocomplete(
        query: request.query.trim(),
        customerId: request.customerId,
      );
    } catch (e, stackTrace) {
      debugPrint('addressAutocompleteProvider fetch failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      // Surface the error to the UI via AsyncError so the field can show
      // the retry hint; do not throw out of the provider.
      rethrow;
    }
  },
);