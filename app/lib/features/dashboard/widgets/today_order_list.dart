import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show statusMap;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/widgets/collapsible_category_sections.dart';
import '../../orders/widgets/order_card.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// All order statuses in workflow order, including terminal statuses
/// (completed, cancelled). Used by [TodayOrderList] to group today's orders
/// (FR6/AC6 — DG-376 Phase 5).
const todayOrderStatuses = <String>[
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
  'completed',
  'cancelled',
];

/// Groups today's orders by status in workflow order (FR6/AC6).
///
/// Returns an ordered map keyed by status code. Only statuses with at least
/// one order appear in the result. Within each group, orders sort by
/// `dueDate` ascending (null/empty first), then `dueTime` ascending —
/// mirroring [groupDeliveryOrdersByStatus] in `delivery_helpers.dart`.
Map<String, List<Order>> groupTodayOrdersByStatus(List<Order> orders) {
  final result = <String, List<Order>>{};
  for (final status in todayOrderStatuses) {
    final statusOrders = orders.where((o) => o.status == status).toList();
    if (statusOrders.isEmpty) continue;
    statusOrders.sort((a, b) {
      final aHasDate = a.dueDate != null && a.dueDate!.isNotEmpty;
      final bHasDate = b.dueDate != null && b.dueDate!.isNotEmpty;
      if (!aHasDate && bHasDate) return -1;
      if (aHasDate && !bHasDate) return 1;
      if (!aHasDate && !bHasDate) return 0;
      final dateCmp = a.dueDate!.compareTo(b.dueDate!);
      if (dateCmp != 0) return dateCmp;
      final aTime = a.dueTime ?? '';
      final bTime = b.dueTime ?? '';
      return aTime.compareTo(bTime);
    });
    result[status] = statusOrders;
  }
  return result;
}

/// Today's order list grouped by status with a count per group (FR6/AC6).
///
/// Renders all orders due today (including completed and cancelled) grouped
/// under workflow-ordered section headers. Each header shows a colored status
/// dot, the localized status label, a count badge, and a collapse/expand
/// chevron — reusing the [CategorySectionExpansionController] pattern from
/// [CollapsibleCategorySections]. Tapping a header toggles the group's
/// collapse state (DG-386 Phase 10 / FR6 / AC6). When collapsed, only the
/// header (status label + count) is shown; when expanded, the [OrderCard]
/// list renders below. All groups default to expanded so the pre-Phase-10
/// behavior is preserved.
///
/// The orders come from the today-summary API response
/// ([TodaySummary.orders]) — no separate order fetch is needed. An empty
/// list renders a centered empty-state message.
class TodayOrderList extends StatefulWidget {
  const TodayOrderList({
    super.key,
    required this.orders,
    this.onOrderTap,
  });

  /// All orders due today (any status), as returned by the today-summary API.
  final List<Order> orders;

  /// Optional tap handler for an order row. Defaults to navigating to the
  /// order detail screen via the order ref.
  final void Function(Order order)? onOrderTap;

  @override
  State<TodayOrderList> createState() => _TodayOrderListState();
}

class _TodayOrderListState extends State<TodayOrderList> {
  late final CategorySectionExpansionController _expansionController;

  /// Status keys that have already been seeded with an explicit expand/collapse
  /// state. Used by [didUpdateWidget] to distinguish a newly-appeared status
  /// group (seed it expanded) from one the user has already toggled (preserve
  /// their choice) — [CategorySectionExpansionController.isExpanded] returns
  /// `false` for both unseeded keys and explicitly-collapsed keys (Mn-3).
  final Set<String> _seededStatuses = <String>{};

  @override
  void initState() {
    super.initState();
    _expansionController = CategorySectionExpansionController();
    // All groups default to expanded so the pre-Phase-10 behavior (always
    // visible) is preserved until the user taps a header (DG-386 Phase 10).
    final grouped = groupTodayOrdersByStatus(widget.orders);
    for (final status in grouped.keys) {
      _expansionController.setExpanded(status, true);
      _seededStatuses.add(status);
    }
  }

  @override
  void didUpdateWidget(covariant TodayOrderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Seed expansion for any status group that newly appears after a refresh
    // (Mn-3). Preserves the expand-by-default contract: a group that was not
    // present in `initState` but appears on an updated `widget.orders` is
    // expanded here. Groups that already have a recorded state keep their
    // user-toggled value — only keys absent from `_seededStatuses` are seeded.
    final grouped = groupTodayOrdersByStatus(widget.orders);
    for (final status in grouped.keys) {
      if (_seededStatuses.add(status)) {
        _expansionController.setExpanded(status, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          SharedLabels.khongCoDonHomNay,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final grouped = groupTodayOrdersByStatus(widget.orders);
    final children = <Widget>[];
    for (final entry in grouped.entries) {
      final status = entry.key;
      final orders = entry.value;
      final expanded = _expansionController.isExpanded(status);
      children.add(
        _TodayStatusGroupHeader(
          status: status,
          count: orders.length,
          isCollapsed: !expanded,
          onTap: () {
            setState(() {
              _expansionController.setExpanded(status, !expanded);
              // Record the user's explicit choice so a later refresh does not
              // re-seed this group via `didUpdateWidget` (Mn-3).
              _seededStatuses.add(status);
            });
          },
        ),
      );
      if (expanded) {
        for (final order in orders) {
          children.add(
            OrderCard(
              order: order,
              onTap: () {
                if (widget.onOrderTap != null) {
                  widget.onOrderTap!(order);
                  return;
                }
                context.push('/orders/${order.orderRef}');
              },
            ),
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Status-group header for [TodayOrderList]: a colored status dot, the
/// localized status label, a count badge, and a collapse/expand chevron.
/// Mirrors the visual pattern of [DeliveryStatusGroupHeader] (delivery list
/// view) but is a separate widget so the today-sales list can evolve
/// independently. Tapping the header toggles the group's collapse state
/// (DG-386 Phase 10 / FR6 / AC6).
class _TodayStatusGroupHeader extends StatelessWidget {
  const _TodayStatusGroupHeader({
    required this.status,
    required this.count,
    required this.isCollapsed,
    required this.onTap,
  });

  final String status;
  final int count;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = BakeryTheme.statusColors[status] ?? Colors.grey;
    final statusLabel = statusMap[status] ?? status;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}