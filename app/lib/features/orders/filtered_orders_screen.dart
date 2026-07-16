import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/labels/orders.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/order_helpers.dart';
import 'widgets/order_card.dart';

/// Active (non-terminal) order statuses used by both banner counts and the
/// filtered listings so the two stay in sync.
const activeFilterStatuses = <String>[
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
];

/// Filters [orders] to those with urgency critical OR urgent AND an active
/// (non-terminal) status. Used by the urgency filtered listing reached by
/// tapping the urgency banner — must match the banner's count.
List<Order> filterUrgencyActive(List<Order> orders) {
  return orders
      .where(
        (o) =>
            (o.urgency == urgencyCritical || o.urgency == urgencyUrgent) &&
            activeFilterStatuses.contains(o.status),
      )
      .toList();
}

/// Filters [orders] to those with completeness incomplete AND an active
/// (non-terminal) status. Used by the incomplete filtered listing reached by
/// tapping the incomplete banner — must match the banner's count.
List<Order> filterIncompleteActive(List<Order> orders) {
  return orders
      .where(
        (o) =>
            o.completeness == completenessIncomplete &&
            activeFilterStatuses.contains(o.status),
      )
      .toList();
}

/// Counts active (non-terminal) orders with urgency critical. Used by the
/// urgency banner's critical chip.
int countCriticalActive(List<Order> orders) {
  return orders
      .where(
        (o) => o.urgency == urgencyCritical && activeFilterStatuses.contains(o.status),
      )
      .length;
}

/// Counts active (non-terminal) orders with urgency urgent. Used by the
/// urgency banner's urgent chip.
int countUrgentActive(List<Order> orders) {
  return orders
      .where(
        (o) => o.urgency == urgencyUrgent && activeFilterStatuses.contains(o.status),
      )
      .length;
}

/// Counts active (non-terminal) incomplete orders. Used by the incomplete
/// banner.
int countIncompleteActive(List<Order> orders) {
  return orders
      .where(
        (o) =>
            o.completeness == completenessIncomplete &&
            activeFilterStatuses.contains(o.status),
      )
      .length;
}

class FilteredOrdersScreen extends ConsumerStatefulWidget {
  const FilteredOrdersScreen({super.key, required this.filter});

  final String filter;

  @override
  ConsumerState<FilteredOrdersScreen> createState() =>
      _FilteredOrdersScreenState();
}

class _FilteredOrdersScreenState extends ConsumerState<FilteredOrdersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isIncomplete => widget.filter == 'incomplete';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _statuses => activeFilterStatuses;

  String get _title =>
      _isIncomplete ? OrdersLabels.incompleteBannerTitle : OrdersLabels.combinedUrgencyTitle;

  String get _emptyText =>
      _isIncomplete ? OrdersLabels.incompleteFilterEmpty : OrdersLabels.urgencyFilterEmpty;

  List<Order> _applySearch(List<Order> orders) {
    if (_searchQuery.trim().isEmpty) return orders;
    final q = _searchQuery.trim().toLowerCase();
    return orders.where((o) {
      return o.customerName.toLowerCase().contains(q) ||
          o.customerPhone.contains(q) ||
          o.orderRef.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);
    final notifier = ref.read(orderListProvider.notifier);

    List<Order> applyFilter(List<Order> orders) {
      if (_isIncomplete) {
        return filterIncompleteActive(orders);
      }
      return filterUrgencyActive(orders);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: VN.lichSuDonHangTimKiem,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(VN.apiError),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: notifier.refresh,
                        child: const Text(VN.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (orders) {
                final filtered = applyFilter(orders);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _emptyText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                final searched = _applySearch(filtered);
                if (searched.isEmpty) {
                  return const Center(
                    child: Text(VN.lichSuDonHangKhongTimThay),
                  );
                }

                final grouped = <String, List<Order>>{};
                for (final status in _statuses) {
                  grouped[status] = <Order>[];
                }
                for (final order in searched) {
                  grouped
                      .putIfAbsent(order.status, () => <Order>[])
                      .add(order);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    for (final status in _statuses)
                      if ((grouped[status] ?? const <Order>[])
                          .isNotEmpty) ...[
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(4, 8, 4, 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: BakeryTheme
                                          .statusColors[status] ??
                                      Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                statusMap[status] ?? status,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        ...grouped[status]!.map(
                          (order) => OrderCard(
                            order: order,
                            onTap: () => context
                                .push('/orders/${order.orderRef}'),
                          ),
                        ),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
