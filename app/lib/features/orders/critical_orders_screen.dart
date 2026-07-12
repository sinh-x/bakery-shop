import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/labels/orders.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/order_helpers.dart';
import 'widgets/order_card.dart';

const _statuses = <String>[
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
  'completed',
  'cancelled',
];

class CriticalOrdersScreen extends ConsumerStatefulWidget {
  const CriticalOrdersScreen({super.key});

  @override
  ConsumerState<CriticalOrdersScreen> createState() =>
      _CriticalOrdersScreenState();
}

class _CriticalOrdersScreenState extends ConsumerState<CriticalOrdersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

    List<Order> criticalOnly(List<Order> orders) =>
        orders.where((o) => o.urgency == urgencyCritical).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.criticalOrdersTitle),
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
                final critical = criticalOnly(orders);
                if (critical.isEmpty) {
                  return const Center(
                    child: Text(OrdersLabels.urgencyFilterEmpty),
                  );
                }

                final filtered = _applySearch(critical);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(VN.lichSuDonHangKhongTimThay),
                  );
                }

                final grouped = <String, List<Order>>{};
                for (final status in _statuses) {
                  grouped[status] = <Order>[];
                }
                for (final order in filtered) {
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
