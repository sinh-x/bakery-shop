import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/models/order.dart';
import '../../../../shared/labels/orders.dart';
import '../../../../shared/theme/bakery_theme.dart';
import '../../../../shared/utils/delivery_helpers.dart';

/// Mini order card rendered inside calendar time-slot rows and the
/// unscheduled row (DG-329 Phase 4 / FR5 / NFR2). Tapping navigates to the
/// order detail screen.
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2). This is an
/// implementation-detail widget of the day/week calendar views and is not
/// intended for reuse outside the calendar grids.
///
/// [compact] selects between two layouts:
/// - `false` (default): the card fills the available width inside a
///   `ListView` (used by the unscheduled row and the narrow-screen
///   fallback).
/// - `true`: the card renders with a minimum readable width of
///   [OrdersLabels.compactOrderChipMinWidth] pixels and is intended for use
///   inside a `Wrap` (max 4 per row on screens ≥ 480px).
class CompactMiniOrderCard extends StatelessWidget {
  const CompactMiniOrderCard({super.key, required this.order, this.compact = false});

  final Order order;

  final bool compact;

  /// Resolves the assigned staff display name for the mini-card (DG-329
  /// Phase 2 / FR3 / AC2). The backend already JOINs the real staff name
  /// (including deactivated staff whose `staff` row still exists), so the
  /// common case returns [Order.assignedStaffName] directly. When the name
  /// is empty (staff record deleted), falls back to "NV #`<id>`" using the
  /// id — never the misleading "NV #`<id>` (đã ngưng)" combo.
  ///
  /// CQ-3 (DG-329 Phase 5.6-c1 review remediation): this method intentionally
  /// diverges from the shared [resolveAssignedStaffDisplayName] helper in
  /// `delivery_helpers.dart`. The shared helper performs a client-side
  /// `staffList` lookup (step 2) which requires a Riverpod `WidgetRef` to
  /// read `staffListProvider`. This widget is a plain `StatelessWidget`
  /// rendered deep inside the calendar grid (potentially many instances per
  /// screen), so plumbing a `WidgetRef`/staff list through every calendar
  /// sub-widget would couple the grid to the provider graph and add per-card
  /// lookups for no functional gain: the backend already JOINs the staff name
  /// into [Order.assignedStaffName], so the shared helper's step 2 (empty
  /// backend name → client-side staff list lookup) is effectively dead code
  /// for the calendar path. The remaining two steps (return the backend
  /// name; fall back to "NV #`<id>`" when the staff record is missing) are
  /// reproduced here exactly as in the shared helper. Deactivated-staff
  /// detection (`isAssignedStaffInactive`) is irrelevant here because the
  /// mini-card never appends the "(đã ngưng)" suffix. Do not "fix" this by
  /// calling the shared helper without first refactoring the calendar to
  /// receive a pre-resolved name from its parent (the recommended long-term
  /// option in the review report).
  String _assignedStaffDisplay(Order o) {
    if (o.assignedStaffName.isNotEmpty) return o.assignedStaffName;
    final id = o.assignedStaffId;
    if (id != null && id.isNotEmpty) return OrdersLabels.assignStaffMissing(id);
    return OrdersLabels.deliveryUnassigned;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final slot = deriveTimeSlot(order.dueTime);
    final card = Material(
      color: statusColor.withAlpha(25),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${order.orderRef}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      order.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (slot != null)
                      Text(
                        slot,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    if (order.isAssigned)
                      Text(
                        '${OrdersLabels.deliveryStaffLabel}: ${_assignedStaffDisplay(order)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Text(
                        OrdersLabels.deliveryUnassigned,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: card,
      );
    }
    // Compact variant: enforce minimum readable width (NFR2) so the chip is
    // legible inside the `Wrap` layout. The `SizedBox` provides the lower
    // bound; `Wrap` governs the upper bound by flowing chips to the next
    // row when the available width is exhausted.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: OrdersLabels.compactOrderChipMinWidth,
      ),
      child: card,
    );
  }
}