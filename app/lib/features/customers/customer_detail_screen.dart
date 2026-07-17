import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/customer.dart';
import '../../data/models/order.dart';
import '../../features/auth/auth_provider.dart';
import '../../providers/customers_provider.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'customer_form.dart';

/// Customer detail screen (FR13/AC4).
///
/// Shows the customer profile (name + phone + created date), their linked
/// order history with status and total, and an edit action. Tapping an order
/// navigates to the existing order detail screen.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: const Text(VN.deleteCustomerConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(VN.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(VN.deleteCustomer),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(customerServiceProvider).deleteCustomer(customerId);
      ref.invalidate(customerListProvider);
      if (context.mounted) {
        showTopSnackBar(context, VN.customerDeleted);
        Navigator.of(context).pop();
      }
    } on DioException catch (e) {
      // Surface the backend's centralized VN guidance (409 linked-orders
      // message, 403 admin-only) when present; fall back to a generic VN
      // error label so the user never sees a raw DioException string.
      if (!context.mounted) return;
      final detail = extractBackendDetail(e.response?.data);
      showTopSnackBar(context, detail ?? CustomersLabels.customerDeleteFailed);
    } catch (_) {
      if (context.mounted) {
        showTopSnackBar(context, CustomersLabels.customerDeleteFailed);
      }
    }
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    final async = ref.read(customerProvider(customerId));
    final customer = async.value;
    if (customer == null) return;
    final saved = await showCustomerForm(context, customer: customer);
    if (saved == true && context.mounted) {
      ref.invalidate(customerProvider(customerId));
      ref.invalidate(customerOrdersProvider(customerId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerProvider(customerId));
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    // FR10/AC7: DELETE /api/customers/{id} is admin-only (remediation Mn5).
    // Hide the delete menu item for non-admin roles so staff never see a
    // dead action that always 403s.
    final isAdmin = ref.watch(authProvider).isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.customerListTitle),
        actions: [
          AppBarOverflowMenu(
            items: [
              const PopupMenuItem<String>(
                value: 'edit_customer',
                child: Text(VN.editCustomer),
              ),
              if (isAdmin)
                const PopupMenuItem<String>(
                  value: 'delete_customer',
                  child: Text(VN.deleteCustomer),
                ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'edit_customer':
                  _openEdit(context, ref);
                case 'delete_customer':
                  _confirmDelete(context, ref);
              }
            },
          ),
        ],
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(VN.apiError),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(customerProvider(customerId)),
                icon: const Icon(Icons.refresh),
                label: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (customer) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerProvider(customerId));
            ref.invalidate(customerOrdersProvider(customerId));
          },
          child: ListView(
            children: [
              _CustomerProfileCard(customer: customer),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  VN.customerOrderHistory,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ordersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(VN.apiError),
                ),
                data: (orderJsonList) {
                  if (orderJsonList.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text(VN.customerNoOrders)),
                    );
                  }
                  final orders = orderJsonList.map(Order.fromJson).toList();
                  return Column(
                    children: [
                      for (final order in orders)
                    _CustomerOrderTile(order: order),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerProfileCard extends StatelessWidget {
  const _CustomerProfileCard({required this.customer});

  final Customer customer;

  /// Builds one line per phone number, falling back to the legacy
  /// denormalized [Customer.phone] when [Customer.phones] is empty
  /// (e.g. pre-v58 data or older API responses).
  ///
  /// The primary phone is highlighted with a filled star icon and bold text;
  /// secondary phones use a plain text style (AC9).
  List<Widget> _buildPhoneLines(ThemeData theme) {
    final phones = customer.phones;
    if (phones.isEmpty) {
      if (customer.phone.isEmpty) return const [];
      return [
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.star, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                customer.phone,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ];
    }
    return [
      for (final entry in phones) ...[
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              entry.isPrimary ? Icons.star : Icons.star_border,
              size: 16,
              color: entry.isPrimary ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${entry.phone}${entry.isPrimary ? ' (${VN.customerPrimaryPhone})' : ''}',
                style: entry.isPrimary
                    ? theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Text(
                customer.name.isEmpty ? '?' : customer.name[0],
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: theme.textTheme.titleMedium,
                  ),
                  ..._buildPhoneLines(theme),
                  const SizedBox(height: 4),
                  Text(
                    '${VN.customerCreatedAt}: ${formatDisplayDate(customer.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerOrderTile extends StatelessWidget {
  const _CustomerOrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    final statusColor =
        BakeryTheme.statusColors[status] ?? Colors.grey;
    final statusLabel = statusMap[status] ?? status;

    return ListTile(
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(order.orderRef),
      subtitle: Text(formatDisplayDate(order.dueDate != null
          ? DateTime.tryParse(order.dueDate!) ?? order.createdAt
          : order.createdAt)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatVND(order.totalPrice),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            statusLabel,
            style: TextStyle(color: statusColor, fontSize: 12),
          ),
        ],
      ),
      onTap: () => context.push('/orders/${order.orderRef}'),
    );
  }
}