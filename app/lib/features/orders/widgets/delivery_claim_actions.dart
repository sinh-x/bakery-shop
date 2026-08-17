import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/staff_service.dart';
import '../../../data/models/order.dart';
import '../../../data/providers/staff_provider.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/delivery_helpers.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../orders/providers/delivery_claim_handler.dart';
import '../../orders/providers/delivery_claim_providers.dart';

/// Claim/unclaim button + assigned-staff name display for delivery order
/// cards (DG-310 Phase 4 / FR5/FR6/FR7/AC6/AC7/AC8/AC9).
///
/// Role-gating (AC9): the claim button renders when the current staff
/// is any linked staff member (or is an admin). Single-assignee (AC10) is
/// enforced server-side; the button is hidden when the order is already
/// claimed by someone else.
///
/// DG-329 Phase 2 / FR3 / AC2: the assigned staff name is resolved via
/// [resolveAssignedStaffDisplayName] so the real name shows (the backend
/// already JOINs the staff name, including deactivated staff). When the
/// staff record is missing entirely (deleted), the "NV #`<id>`" fallback is
/// shown instead of an empty name — never the misleading
/// "NV #`<id>` (đã ngưng)" combo.
class DeliveryClaimActions extends ConsumerWidget {
  const DeliveryClaimActions({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);
    final allStaffAsync = ref.watch(staffListProvider);
    final theme = Theme.of(context);

    final isTerminal = !activeOrderStatuses.contains(order.status);

    return staffAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (staff) {
        final canShowButtons = !isTerminal && staff.canClaim;
        final canUnclaim = order.isAssigned &&
            staff.canUnclaim &&
            (staff.isAdmin || order.isClaimedBy(staff.staffIdAsString));
        final canClaim = canShowButtons && !order.isAssigned;

        final allStaff = allStaffAsync.maybeWhen(
          data: (list) => list,
          orElse: () => const <StaffMember>[],
        );
        final displayName = resolveAssignedStaffDisplayName(
          assignedStaffId: order.assignedStaffId,
          assignedStaffName: order.assignedStaffName,
          staffList: allStaff,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (order.isAssigned && displayName != null)
              _AssignedStaffName(name: displayName, theme: theme)
            else if (canShowButtons)
              Text(
                OrdersLabels.deliveryUnassigned,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            if (canClaim || canUnclaim) ...[
              const SizedBox(height: 4),
              _ClaimButton(
                isClaiming: claimAsync.isLoading,
                canClaim: canClaim,
                canUnclaim: canUnclaim,
                onClaim: () => handleDeliveryClaimAction(
                  context,
                  ref,
                  order.orderRef,
                  isClaim: true,
                ),
                onUnclaim: () => handleDeliveryClaimAction(
                  context,
                  ref,
                  order.orderRef,
                  isClaim: false,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AssignedStaffName extends StatelessWidget {
  const _AssignedStaffName({required this.name, required this.theme});
  final String name;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.person_outline,
          size: 14,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(width: 4),
        Text(
          '${OrdersLabels.deliveryClaimedBy}: $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.tertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.isClaiming,
    required this.canClaim,
    required this.canUnclaim,
    required this.onClaim,
    required this.onUnclaim,
  });

  final bool isClaiming;
  final bool canClaim;
  final bool canUnclaim;
  final VoidCallback onClaim;
  final VoidCallback onUnclaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (canClaim) {
      return FilledButton.tonalIcon(
        onPressed: isClaiming ? null : onClaim,
        icon: isClaiming
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.pan_tool_outlined, size: 16),
        label: const Text(OrdersLabels.deliveryClaimButton),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: isClaiming ? null : onUnclaim,
      icon: isClaiming
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.undo_outlined, size: 16, color: theme.colorScheme.error),
      label: Text(
        OrdersLabels.deliveryUnclaimButton,
        style: TextStyle(color: theme.colorScheme.error),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}