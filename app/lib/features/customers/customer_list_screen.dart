import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers/customers_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/customer_list.dart';
import 'widgets/customer_list_skeleton.dart';
import 'customer_form.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Customer management screen (FR12).
///
/// Lists all customers with a search bar (FR1/AC5), a create button, and
/// tappable rows that navigate to the customer detail screen (FR13/AC4).
class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(customerSearchProvider.notifier).set(query);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(customerSearchProvider.notifier).clear();
  }

  void _openCreateForm() async {
    await showCustomerForm(
      context,
      onUseExisting: (c) => context.push('/customers/${c.id}'),
    );
    if (mounted) {
      // DG-409 Phase 4: refresh the paginated customer list after a create so
      // the new customer appears. Also invalidate the legacy provider kept
      // for detail/form invalidation hooks.
      await ref.read(customerPaginationProvider.notifier).refresh();
      ref.invalidate(customerListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // DG-409 Phase 4 (FR11, AC4): paginated customer list with server-side
    // search. The legacy customerListProvider stays for invalidation hooks
    // (detail/form/duplicate-finder); the screen reads the paginated state.
    final paginationAsync = ref.watch(customerPaginationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(CustomersLabels.manageCustomers),
        actions: const [AppBarOverflowMenu()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: CustomersLabels.searchCustomers,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                        tooltip: OrdersLabels.clear,
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: paginationAsync.when(
              loading: () => const CustomerListSkeleton(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(SharedLabels.apiError),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(customerPaginationProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text(SharedLabels.retry),
                    ),
                  ],
                ),
              ),
              data: (state) => CustomerList(
                state: state,
                onRefresh: () =>
                    ref.read(customerPaginationProvider.notifier).refresh(),
                onLoadMore: () =>
                    ref.read(customerPaginationProvider.notifier).loadMore(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: CustomersLabels.addCustomer,
        onPressed: _openCreateForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}