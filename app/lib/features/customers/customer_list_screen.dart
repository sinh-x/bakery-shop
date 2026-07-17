import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/customer.dart';
import '../../providers/customers_provider.dart';
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

  Future<void> _openCreateForm() async {
    await showCustomerForm(
      context,
      onUseExisting: (c) => context.push('/customers/${c.id}'),
    );
    if (mounted) {
      await ref.read(customerListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerListProvider);

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
            child: customersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
                          ref.read(customerListProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (customers) => _CustomerList(
                customers: customers,
                onRefresh: () =>
                    ref.read(customerListProvider.notifier).refresh(),
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
  const _CustomerList({required this.customers, required this.onRefresh});

  final List<Customer> customers;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: customers.length,
        itemBuilder: (context, index) {
          final customer = customers[index];
          return _CustomerTile(customer: customer);
        },
        separatorBuilder: (_, _) => const Divider(height: 1),
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