import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/staff_service.dart';
import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../providers/staff_provider.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'delivery_day_calendar_view.dart';
import 'delivery_order_card.dart';
import 'delivery_week_calendar_view.dart';

/// Delivery tab content: status-grouped delivery order list with day/week
/// calendar views, today/all filter, and (DG-304 Phase 4) a staff filter
/// dropdown + per-staff workload summary.
///
/// The staff filter is session-only — it resets to "All" when the user
/// navigates away from the delivery tab (AC7). Pass the host [TabController]
/// via [tabController] so this widget can listen for tab switches; when null
/// (e.g. in tests) no reset-on-leave behavior is wired.
class DeliveryContent extends ConsumerStatefulWidget {
  const DeliveryContent({super.key, this.tabController});

  /// Optional host tab controller used to reset the staff filter to "All"
  /// when the user navigates away from the delivery tab (AC7).
  final TabController? tabController;

  @override
  ConsumerState<DeliveryContent> createState() => _DeliveryContentState();
}

class _DeliveryContentState extends ConsumerState<DeliveryContent> {
  bool _showToday = true;

  /// View mode for the delivery tab: 'day' (default), 'week', or 'list'.
  /// Defaults to 'day' per FR1/AC1 so the day calendar is shown on open.
  String _viewMode = 'day';

  /// Selected delivery-staff filter id (FR2/FR3). `null` = "All" (FR4).
  /// Session-only: reset to `null` on tab leave (AC7).
  String? _selectedStaffId;

  TabController? _observedTabController;

  @override
  void initState() {
    super.initState();
    _attachTabController(widget.tabController);
  }

  @override
  void didUpdateWidget(covariant DeliveryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      _attachTabController(widget.tabController);
    }
  }

  @override
  void dispose() {
    _detachTabController();
    super.dispose();
  }

  void _attachTabController(TabController? controller) {
    _detachTabController();
    _observedTabController = controller;
    controller?.addListener(_handleTabChange);
  }

  void _detachTabController() {
    _observedTabController?.removeListener(_handleTabChange);
    _observedTabController = null;
  }

  /// Resets the staff filter to "All" (null) whenever the delivery tab is
  /// not the active tab (AC7). The delivery tab is index 2 in
  /// `OrderListScreen`'s 3-tab controller. The `setState` is a no-op when
  /// the filter is already null, so it is safe to call on every tab
  /// notification. The host `OrderListScreen` also rebuilds on tab changes,
  /// so `_maybeResetStaffFilterOnTabLeave` (called from `build`) catches
  /// any transition the listener misses.
  void _handleTabChange() {
    final controller = _observedTabController;
    if (controller == null) return;
    if (controller.index != 2 && _selectedStaffId != null) {
      setState(() => _selectedStaffId = null);
    }
  }

  /// Defense-in-depth: also reset during `build` when the host rebuilds us
  /// while off the delivery tab (covers `TabController` notify quirks).
  void _maybeResetStaffFilterOnTabLeave() {
    final controller = _observedTabController;
    if (controller == null) return;
    if (controller.index != 2 && _selectedStaffId != null) {
      _selectedStaffId = null;
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  /// All active staff filtered client-side from the cached
  /// `staffListProvider` (FR2/NFR1 — no extra API call on toggle).
  List<StaffMember> _deliveryStaff(List<StaffMember> all) {
    return all.where((s) => s.active).toList();
  }

  @override
  Widget build(BuildContext context) {
    _maybeResetStaffFilterOnTabLeave();
    final ordersAsync = ref.watch(orderListProvider);
    final staffAsync = ref.watch(staffListProvider);
    final deliveryStaff = staffAsync.maybeWhen(
      data: _deliveryStaff,
      orElse: () => const <StaffMember>[],
    );

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _onRefresh,
              child: const Text(VN.retry),
            ),
          ],
        ),
      ),
      data: (orders) {
        final isCalendar = _viewMode != 'list';
        // The week/day grid has its own "Hôm nay" navigation (FR5/AC2/AC3),
        // so it always receives all non-terminal delivery orders regardless
        // of the Today/All filter. The Today/All filter only applies to the
        // list view. The staff filter (FR3) applies to both calendar and
        // list views.
        final calendarOrders = filterDeliveryOrdersByStaff(
          filterDeliveryOrders(orders, todayOnly: false),
          staffId: _selectedStaffId,
        );
        final listOrders = filterDeliveryOrdersByStaff(
          filterDeliveryOrders(orders, todayOnly: _showToday),
          staffId: _selectedStaffId,
        );
        // Auto-focus the WEEK calendar on the next upcoming non-terminal
        // delivery order (FR2/FR3/AC2); fall back to today when none
        // (AC4). The DAY calendar always defaults to today (FR4/AC3) —
        // see `_buildView`. Computed once per rebuild from the
        // non-terminal set.
        final nextDue = findNextDueDate(calendarOrders) ?? DateTime.now();
        final nextDueWeekStart = startOfWeek(nextDue);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  if (!isCalendar) ...[
                    FilterChip(
                      label: const Text(OrdersLabels.deliveryFilterToday),
                      selected: _showToday,
                      onSelected: (v) => setState(() => _showToday = v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text(OrdersLabels.deliveryFilterAll),
                      selected: !_showToday,
                      onSelected: (v) => setState(() => _showToday = !v),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _StaffFilterDropdown(
                    deliveryStaff: deliveryStaff,
                    selectedStaffId: _selectedStaffId,
                    onChanged: (id) =>
                        setState(() => _selectedStaffId = id),
                  ),
                  const Spacer(),
                  _ViewModeToggle(
                    viewMode: _viewMode,
                    onChanged: (mode) =>
                        setState(() => _viewMode = mode),
                  ),
                ],
              ),
            ),
            _WorkloadSummary(
              deliveryStaff: deliveryStaff,
              todayOrders: filterDeliveryOrders(orders, todayOnly: true),
            ),
            Expanded(
              child: _buildView(calendarOrders, listOrders, nextDueWeekStart),
            ),
          ],
        );
      },
    );
  }

  Widget _buildView(
    List<Order> calendarOrders,
    List<Order> listOrders,
    DateTime nextDueWeekStart,
  ) {
    switch (_viewMode) {
      case 'week':
        return DeliveryWeekCalendarView(
          orders: calendarOrders,
          onRefresh: _onRefresh,
          initialWeekStart: nextDueWeekStart,
        );
      case 'day':
        // Day calendar always defaults to today (FR4/AC3) — the
        // current-time line requires viewing today, and "next due" may
        // be a future date with no orders today. The week calendar keeps
        // the "next due" auto-focus (FR2/FR3/AC2); only the day calendar
        // anchors to today.
        return DeliveryDayCalendarView(
          orders: calendarOrders,
          onRefresh: _onRefresh,
        );
      default:
        if (listOrders.isEmpty) {
          return Center(
            child: Text(
              _showToday
                  ? OrdersLabels.deliveryEmptyToday
                  : OrdersLabels.deliveryEmptyAll,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }
        return _buildGroupedList(listOrders);
    }
  }

  Widget _buildGroupedList(List<Order> orders) {
    final grouped = groupDeliveryOrdersByStatus(orders);
    final items = <Object>[];
    for (final entry in grouped.entries) {
      if (entry.value.isNotEmpty) {
        items.add(entry.key);
        items.addAll(entry.value);
      }
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: items.length,
        itemBuilder: (ctx, index) {
          final item = items[index];
          if (item is String) {
            final statusColor =
                BakeryTheme.statusColors[item] ?? Colors.grey;
            final statusLabel = statusMap[item] ?? item;
            final sectionOrders = grouped[item]!;
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${sectionOrders.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final order = item as Order;
          return DeliveryOrderCard(
            order: order,
            onTap: () => ctx.push('/orders/${order.orderRef}'),
          );
        },
      ),
    );
  }
}

/// Staff filter dropdown populated from all active staff (FR2/FR4).
/// "All" is always the first option and the default selection (FR4).
/// No extra API call on toggle (NFR1) — uses already-loaded staff.
class _StaffFilterDropdown extends StatelessWidget {
  const _StaffFilterDropdown({
    required this.deliveryStaff,
    required this.selectedStaffId,
    required this.onChanged,
  });

  final List<StaffMember> deliveryStaff;
  final String? selectedStaffId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Ensure the current selection is still in the list (e.g. after a
    // refresh); otherwise fall back to "All".
    final value = (selectedStaffId == null ||
            deliveryStaff.any((s) => s.id.toString() == selectedStaffId))
        ? selectedStaffId
        : null;

    return DropdownButton<String?>(
      value: value,
      hint: const Text(OrdersLabels.staffFilterLabel),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text(OrdersLabels.staffFilterAll),
        ),
        ...deliveryStaff.map(
          (s) => DropdownMenuItem<String?>(
            value: s.id.toString(),
            child: Text(s.name),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Per-staff workload summary (FR6/AC5): shows each active staff
/// member's count of today's non-terminal delivery orders, plus an
/// "unassigned" bucket. Renders for ALL active staff regardless of role
/// (not just `giao-hang`) — Phase 1 expanded `_deliveryStaff` to all
/// active staff, so the summary now appears whenever any active staff
/// exist. Collapses to the empty-state label when there are no active
/// staff and hides entirely when the staff list is still loading.
class _WorkloadSummary extends StatelessWidget {
  const _WorkloadSummary({
    required this.deliveryStaff,
    required this.todayOrders,
  });

  final List<StaffMember> deliveryStaff;
  final List<Order> todayOrders;

  @override
  Widget build(BuildContext context) {
    if (deliveryStaff.isEmpty) return const SizedBox.shrink();

    final summary = computeWorkloadSummary(todayOrders, deliveryStaff);
    final theme = Theme.of(context);

    final chips = <Widget>[];
    for (final entry in summary.entries) {
      chips.add(
        Chip(
          label: Text(
            OrdersLabels.workloadStaffCount(entry.staff.name, entry.count),
            style: theme.textTheme.bodySmall,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      );
    }
    chips.add(
      Chip(
        label: Text(
          '${OrdersLabels.workloadUnassigned}: ${summary.unassignedCount}',
          style: theme.textTheme.bodySmall,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
    );

    final allZero = summary.entries.every((e) => e.count == 0) &&
        summary.unassignedCount == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              allZero
                  ? OrdersLabels.workloadSummaryEmpty
                  : OrdersLabels.workloadSummaryTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
            if (!allZero) ...chips,
          ],
        ),
      ),
    );
  }
}

/// Cycle button that toggles between list → week → day → list views.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onChanged});

  final String viewMode;
  final ValueChanged<String> onChanged;

  IconData _icon() {
    switch (viewMode) {
      case 'list':
        return Icons.calendar_month_outlined;
      case 'week':
        return Icons.view_day_outlined;
      case 'day':
        return Icons.view_list;
      default:
        return Icons.calendar_month_outlined;
    }
  }

  String _tooltip() {
    switch (viewMode) {
      case 'list':
        return OrdersLabels.deliverySwitchToWeek;
      case 'week':
        return OrdersLabels.deliverySwitchToDay;
      case 'day':
        return OrdersLabels.deliverySwitchToList;
      default:
        return OrdersLabels.deliverySwitchToWeek;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon()),
      tooltip: _tooltip(),
      onPressed: () {
        switch (viewMode) {
          case 'list':
            onChanged('week');
          case 'week':
            onChanged('day');
          case 'day':
            onChanged('list');
        }
      },
    );
  }
}