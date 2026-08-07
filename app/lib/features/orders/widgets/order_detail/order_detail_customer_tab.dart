import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/models/customer.dart';
import '../../../../data/models/order.dart';
import '../../../../providers/customers_provider.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import '../order_card.dart';

/// Customer tab content for the order detail screen (DG-371 Phase 1).
///
/// Shows the linked customer's profile (name, phone, created date) and their
/// full order history rendered with the shared [OrderCard] widget (FR8/FR9).
/// When the parent order has no `customerId`, the tab shows the
/// "Chưa có khách hàng" empty state (FR10/AC8).
///
/// The tab reads `customerProvider(customerId)` and
/// `customerOrdersProvider(customerId)` — both Riverpod family providers keyed
/// by `customerId`. Riverpod caches results by family argument, so switching
/// tabs never triggers a refetch as long as the `customerId` stays the same
/// (NFR1). The order history JSON is decoded via `Order.fromJson` (same
/// pattern as `customer_detail_screen.dart` line 172) so the `Order` model
/// stays the single source of truth for the order shape.
class OrderDetailCustomerTab extends ConsumerWidget {
  const OrderDetailCustomerTab({super.key, required this.customerId});

  final int? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = customerId;
    if (id == null) {
      return const _EmptyCustomerState();
    }

    final customerAsync = ref.watch(customerProvider(id));
    final ordersAsync = ref.watch(customerOrdersProvider(id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(
            VN.orderDetailCustomerInfoTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        customerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(VN.apiError),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(customerProvider(id)),
                  icon: const Icon(Icons.refresh),
                  label: const Text(VN.retry),
                ),
              ],
            ),
          ),
          data: (customer) => _CustomerInfoCard(customer: customer),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
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
            // Parse via Order.fromJson — same pattern as
            // customer_detail_screen.dart line 172.
            final orders = orderJsonList.map(Order.fromJson).toList();
            return Column(
              children: [
                for (final order in orders)
                  OrderCard(
                    order: order,
                    onTap: () => context.push(
                      '/orders/${order.orderRef}',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Empty state for an order with no linked customer (FR10/AC8).
class _EmptyCustomerState extends StatelessWidget {
  const _EmptyCustomerState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(VN.orderDetailCustomerEmpty),
          ],
        ),
      ),
    );
  }
}

/// Compact customer profile card for the order detail customer tab (FR8).
///
/// Mirrors the layout of `_CustomerProfileCard` in
/// `customer_detail_screen.dart` but lives here so the order detail tab stays
/// self-contained — the customer detail screen's card is private to that
/// file and carries edit/delete affordances that don't belong on the order
/// detail view.
class _CustomerInfoCard extends StatelessWidget {
  const _CustomerInfoCard({required this.customer});

  final Customer customer;

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
              child: Text(customer.phone, style: theme.textTheme.bodyMedium),
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
    final createdAt = customer.createdAt;
    return Card(
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
                  Text(customer.name, style: theme.textTheme.titleMedium),
                  ..._buildPhoneLines(theme),
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${VN.customerCreatedAt}: ${formatDisplayDate(createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}