import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/customer.dart';
import '../../data/providers/customers_provider.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'widgets/phone_count_badge.dart';
import 'customer_form.dart';

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
        title: const Text(VN.manageCustomers),
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
                hintText: VN.searchCustomers,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                        tooltip: VN.clear,
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: paginationAsync.when(
              loading: () => const _CustomerListSkeleton(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(VN.apiError),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(customerPaginationProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (state) => _CustomerList(
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
        tooltip: VN.addCustomer,
        onPressed: _openCreateForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final CustomerPaginationState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final customers = state.loaded;
    if (customers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(VN.noCustomers),
          ],
        ),
      );
    }

    // DG-409 Phase 4: infinite-scroll via a scroll listener that triggers
    // load-more near the bottom. Combined with the explicit "Tải thêm"
    // affordance below for discoverability.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200 &&
            state.hasMore &&
            !state.isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          itemCount: customers.length + 1,
          itemBuilder: (context, index) {
            if (index == customers.length) {
              return _LoadMoreTile(
                state: state,
                onLoadMore: onLoadMore,
              );
            }
            return _CustomerTile(customer: customers[index]);
          },
          separatorBuilder: (_, _) => const Divider(height: 1),
        ),
      ),
    );
  }
}

/// Footer tile rendered at the end of the customer list. Shows a loading
/// spinner while fetching the next page, a "Tải thêm" button when more pages
/// remain, or nothing when all customers are loaded (DG-409 Phase 4).
class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({required this.state, required this.onLoadMore});

  final CustomerPaginationState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!state.hasMore && !state.isLoadingMore) {
      return const SizedBox.shrink();
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(
            '${VN.loadMore} (${state.total - state.loaded.length})',
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton shown while the first customer page loads (DG-409
/// Phase 4 / loading indicators). Renders placeholder tiles so the screen
/// doesn't flash empty before data arrives.
class _CustomerListSkeleton extends StatelessWidget {
  const _CustomerListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, _) => const ListTile(
        leading: CircleAvatar(child: SizedBox.shrink()),
        title: SizedBox(
          height: 16,
          child: LinearProgressIndicator(),
        ),
        subtitle: SizedBox(height: 12, child: LinearProgressIndicator()),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});

  final Customer customer;

  /// Returns the primary phone number to display in the tile subtitle.
  ///
  /// Prefers the primary entry in [Customer.phones] (multi-phone support,
  /// DG-205 Phase 6); falls back to the legacy denormalized [Customer.phone]
  /// for backward compatibility with pre-v58 data or older API responses.
  String get _primaryPhone {
    if (customer.phones.isEmpty) return customer.phone;
    final primary = customer.phones.firstWhere(
      (p) => p.isPrimary,
      orElse: () => customer.phones.first,
    );
    return primary.phone;
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (_primaryPhone.isNotEmpty) _primaryPhone,
      formatDisplayDate(customer.createdAt),
    ];
    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            child: Text(customer.name.isEmpty ? '?' : customer.name[0]),
          ),
          PhoneCountBadge(phoneCount: customer.phones.length),
        ],
      ),
      title: Text(customer.name),
      subtitle: Text(subtitleParts.join(' • ')),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}