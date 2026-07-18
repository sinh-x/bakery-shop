import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/customer_service.dart';
import '../data/models/customer.dart';

/// Current search query for the customer list. Empty string = no filter.
/// Setting this re-triggers [CustomerListNotifier] via `ref.watch`.
class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final customerSearchProvider =
    NotifierProvider<CustomerSearchNotifier, String>(CustomerSearchNotifier.new);

/// Live-searched customer list. Re-fetches whenever the search query changes
/// (FR1). Empty query returns the unfiltered list.
class CustomerListNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    final search = ref.watch(customerSearchProvider);
    final service = ref.read(customerServiceProvider);
    return service.listCustomers(search: search);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final search = ref.read(customerSearchProvider);
      final service = ref.read(customerServiceProvider);
      return service.listCustomers(search: search);
    });
  }
}

final customerListProvider =
    AsyncNotifierProvider<CustomerListNotifier, List<Customer>>(
  CustomerListNotifier.new,
);

/// Fetches a single customer by id (FR3).
final customerProvider =
    FutureProvider.family<Customer, int>((ref, id) async {
  final service = ref.read(customerServiceProvider);
  return service.getCustomer(id);
});

/// Fetches a customer's order history as raw JSON maps (FR6). Screens decode
/// these via `Order.fromJson` so the Order model stays the single source of
/// truth for order shape.
final customerOrdersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, id) async {
  final service = ref.read(customerServiceProvider);
  return service.getCustomerOrders(id);
});

/// Admin duplicate-finder group list (DG-252 Phase 7 — FR7/AC4).
///
/// AsyncNotifier wrapping `GET /api/customers/duplicates`. Screens call
/// `refresh()` after a successful merge so the merged group disappears and
/// any newly-revealed duplicates reload.
class DuplicateGroupsNotifier
    extends AsyncNotifier<List<DuplicateGroup>> {
  @override
  Future<List<DuplicateGroup>> build() async {
    final service = ref.read(customerServiceProvider);
    final result = await service.listDuplicates();
    return result.groups;
  }

  /// Re-fetches the duplicate groups from the backend (after a merge, manual
  /// refresh, etc.).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(customerServiceProvider);
      final result = await service.listDuplicates();
      return result.groups;
    });
  }
}

final duplicateGroupsProvider =
    AsyncNotifierProvider<DuplicateGroupsNotifier, List<DuplicateGroup>>(
  DuplicateGroupsNotifier.new,
);