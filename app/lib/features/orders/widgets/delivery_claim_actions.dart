import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../orders/providers/delivery_claim_providers.dart';

/// Claim/unclaim button + assigned-staff name display for delivery order
/// cards (DG-310 Phase 4 / FR5/FR6/FR7/AC6/AC7/AC8/AC9).
///
/// Role-gating (AC9): the claim button only renders when the current staff
/// has the `giao-hang` role (or is an admin). Single-assignee (AC10) is
/// enforced server-side; the button is hidden when the order is already
/// claimed by someone else.
class DeliveryClaimActions extends ConsumerWidget {
  const DeliveryClaimActions({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (order.isAssigned)
              _AssignedStaffName(name: order.assignedStaffName, theme: theme)
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
                onClaim: () => _claim(ref, context),
                onUnclaim: () => _unclaim(ref, context),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _claim(WidgetRef ref, BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(orderClaimProvider.notifier);
    notifier.setOrderRef(order.orderRef);
    await notifier.claim();
    final state = ref.read(orderClaimProvider);
    if (state.hasError) {
      messenger.showSnackBar(const SnackBar(content: Text(OrdersLabels.deliveryClaimFailed)));
      return;
    }
    showTopSnackBar(context, OrdersLabels.deliveryClaimSuccess);
  }

  Future<void> _unclaim(WidgetRef ref, BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(orderClaimProvider.notifier);
    notifier.setOrderRef(order.orderRef);
    await notifier.unclaim();
    final state = ref.read(orderClaimProvider);
    if (state.hasError) {
      messenger.showSnackBar(const SnackBar(content: Text(OrdersLabels.deliveryUnclaimFailed)));
      return;
    }
    showTopSnackBar(context, OrdersLabels.deliveryUnclaimSuccess);
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