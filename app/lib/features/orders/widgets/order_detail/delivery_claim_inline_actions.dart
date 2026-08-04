import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/order.dart';
import '../../../../shared/labels/orders.dart';
import '../../../../shared/utils/order_helpers.dart';
import '../../providers/delivery_claim_handler.dart';
import '../../providers/delivery_claim_providers.dart';

/// Inline "Nhận giao" / "Trả đơn" button row for delivery orders shown inside
/// the order detail body (DG-311 Phase 3 / FR4 / AC5).
///
/// Visibility mirrors the order detail context menu (`_shouldShowClaimMenu`
/// logic in `order_detail_screen.dart`): the buttons render only when
///   - the order is a delivery type ([isDeliveryType]),
///   - the order is in an active (non-terminal) status
///     ([activeOrderStatuses]),
///   - and the current staff has `canClaim`.
///
/// When the order is unassigned, the "Nhận giao" button shows. When the
/// order is assigned, the "Trả đơn" button shows only if the current staff is
/// the assignee or an admin (single-assignee is enforced server-side).
///
/// Claim/unclaim is performed through the shared [orderClaimProvider] (Phase 1)
/// — the same notifier used by the context menu — so there is a single API
/// code path. Success/error snackbar feedback reuses the same Phase 1
/// mechanism (`showTopSnackBar` with `OrdersLabels.deliveryClaimSuccess` /
/// `deliveryUnclaimSuccess` / `deliveryClaimFailed` / `deliveryUnclaimFailed`).
///
/// The button layout reuses the compact `FilledButton.tonalIcon` /
/// `OutlinedButton.icon` pattern established by [DeliveryClaimActions].
class DeliveryClaimInlineActions extends ConsumerWidget {
  const DeliveryClaimInlineActions({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);

    return staffAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (staff) {
        // Same visibility rules as the order detail context menu
        // (`_shouldShowClaimMenu` in `order_detail_screen.dart`).
        final isVisible = isDeliveryType(order.deliveryType) &&
            activeOrderStatuses.contains(order.status) &&
            staff.canClaim;
        if (!isVisible) return const SizedBox.shrink();

        final canUnclaim = order.isAssigned &&
            staff.canUnclaim &&
            (staff.isAdmin || order.isClaimedBy(staff.staffIdAsString));
        final canClaim = !order.isAssigned;
        if (!canClaim && !canUnclaim) return const SizedBox.shrink();

        final isClaiming = claimAsync.isLoading;
        return Row(
          children: [
            if (canClaim)
              FilledButton.tonalIcon(
                onPressed: isClaiming
                    ? null
                    : () => handleDeliveryClaimAction(
                          context,
                          ref,
                          order.orderRef,
                          isClaim: true,
                        ),
                icon: isClaiming
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.pan_tool_outlined, size: 16),
                label: const Text(OrdersLabels.deliveryClaimButton),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: isClaiming
                    ? null
                    : () => handleDeliveryClaimAction(
                          context,
                          ref,
                          order.orderRef,
                          isClaim: false,
                        ),
                icon: isClaiming
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.undo_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.error),
                label: Text(
                  OrdersLabels.deliveryUnclaimButton,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        );
      },
    );
  }
}