import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/widgets/vietnamese_labels.dart';

// Active (non-terminal) statuses shown in the summary
const _activeStatuses = [
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(dashboardOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(VN.tabDashboard)),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(dashboardOrdersProvider),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (orders) => _DashboardContent(
          orders: orders,
          onRefresh: () async => ref.invalidate(dashboardOrdersProvider),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.orders,
    required this.onRefresh,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayStr = _dateStr(today);
    final in3Days = today.add(const Duration(days: 3));
    final in3DaysStr = _dateStr(in3Days);

    // Overdue: dueDate < today, status not terminal
    final overdueOrders = orders.where((o) {
      if (o.dueDate == null) return false;
      return o.dueDate!.compareTo(todayStr) < 0 &&
          !['completed', 'cancelled', 'delivered'].contains(o.status);
    }).toList()
      ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

    // Today: dueDate == today
    final todayOrders =
        orders.where((o) => o.dueDate == todayStr).toList();

    // Upcoming: dueDate in (today, today+3 days]
    final upcomingOrders = orders.where((o) {
      if (o.dueDate == null) return false;
      return o.dueDate!.compareTo(todayStr) > 0 &&
          o.dueDate!.compareTo(in3DaysStr) <= 0;
    }).toList()
      ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

    // Status counts for summary
    final statusCounts = {
      for (final s in _activeStatuses)
        s: orders.where((o) => o.status == s).length,
    };

    // Group today's orders by status
    final todayByStatus = <String, List<Order>>{};
    for (final o in todayOrders) {
      todayByStatus.putIfAbsent(o.status, () => []).add(o);
    }

    final hasOrders = overdueOrders.isNotEmpty ||
        todayOrders.isNotEmpty ||
        upcomingOrders.isNotEmpty;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card — counts by active status
          _SummaryCard(statusCounts: statusCounts),
          const SizedBox(height: 16),

          // Overdue section (red)
          if (overdueOrders.isNotEmpty) ...[
            _SectionHeader(
              title: VN.overdueOrders,
              icon: Icons.warning_amber_rounded,
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            ...overdueOrders.map((o) => _OrderCard(order: o, isOverdue: true)),
            const SizedBox(height: 16),
          ],

          // Today section — grouped by status
          if (todayOrders.isNotEmpty) ...[
            _SectionHeader(title: VN.todayOrders),
            const SizedBox(height: 8),
            for (final s in _activeStatuses)
              if (todayByStatus.containsKey(s)) ...[
                _StatusGroupHeader(
                    status: s, count: todayByStatus[s]!.length),
                ...todayByStatus[s]!.map((o) => _OrderCard(order: o)),
              ],
            const SizedBox(height: 16),
          ],

          // Upcoming next 3 days
          if (upcomingOrders.isNotEmpty) ...[
            _SectionHeader(title: VN.upcomingDue),
            const SizedBox(height: 8),
            ...upcomingOrders.map((o) => _OrderCard(order: o)),
          ],

          if (!hasOrders)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Không có đơn hàng sắp đến hạn',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.statusCounts});

  final Map<String, int> statusCounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = statusCounts.values.fold(0, (a, b) => a + b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Tổng: $total đơn đang xử lý',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _activeStatuses)
                  if ((statusCounts[s] ?? 0) > 0)
                    _StatusBadge(status: s, count: statusCounts[s]!),
              ],
            ),
            if (total == 0)
              Text(
                'Không có đơn hàng đang xử lý',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.count});

  final String status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = BakeryTheme.statusColors[status] ?? Colors.grey;
    final label = statusMap[status] ?? status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(60),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.icon, this.color});

  final String title;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
      ],
    );
  }
}

class _StatusGroupHeader extends StatelessWidget {
  const _StatusGroupHeader({required this.status, required this.count});

  final String status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = BakeryTheme.statusColors[status] ?? Colors.grey;
    final label = statusMap[status] ?? status;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label ($count)',
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.isOverdue = false});

  final Order order;
  final bool isOverdue;

  String _formatDue(String? dueDate, String? dueTime) {
    if (dueDate == null) return '';
    // YYYY-MM-DD → DD/MM
    final parts = dueDate.split('-');
    final formatted =
        parts.length == 3 ? '${parts[2]}/${parts[1]}' : dueDate;
    return dueTime != null ? '$formatted $dueTime' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        isOverdue ? Colors.red : (BakeryTheme.statusColors[order.status] ?? Colors.grey);
    final statusLabel = statusMap[order.status] ?? order.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isOverdue ? Colors.red.withAlpha(15) : null,
      shape: isOverdue
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.red, width: 1),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order.orderRef}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status color bar
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              // Order info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderRef,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: statusColor.withAlpha(120)),
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      order.customerName,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (order.dueDate != null) ...[
                          Icon(
                            isOverdue
                                ? Icons.warning_amber_rounded
                                : Icons.schedule,
                            size: 13,
                            color: isOverdue
                                ? Colors.red
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatDue(order.dueDate, order.dueTime),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isOverdue
                                  ? Colors.red
                                  : theme.colorScheme.outline,
                              fontWeight:
                                  isOverdue ? FontWeight.w600 : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          formatVND(order.totalPrice),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
