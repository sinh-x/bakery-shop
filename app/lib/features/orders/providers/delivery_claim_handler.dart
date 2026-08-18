import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show showTopSnackBar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/labels/orders.dart';
import 'delivery_claim_providers.dart';

/// Single shared claim/unclaim code path for all three consumers
/// (DG-311 Phase 4 / FR5 / AC7):
///   - [DeliveryClaimActions] (delivery order cards),
///   - [DeliveryClaimInlineActions] (order detail body inline buttons),
///   - order detail screen context menu (`_handleClaimMenuSelection`).
///
/// Each consumer delegates here instead of duplicating the
/// `setOrderRef` → `claim()`/`unclaim()` → read state → snackbar sequence.
/// Snackbars are top-anchored via [showTopSnackBar] for both success and
/// failure, unifying the previously inconsistent bottom-snackbar error path
/// in [DeliveryClaimActions] with the rest of the app.
///
/// [orderRef] identifies the order being claimed/unclaimed. [isClaim] selects
/// the claim (`true`) or unclaim (`false`) action. [ref] is the caller's
/// [WidgetRef]. [context] is the caller's [BuildContext] (must be mounted by
/// the caller before invoking).
Future<void> handleDeliveryClaimAction(
  BuildContext context,
  WidgetRef ref,
  String orderRef, {
  required bool isClaim,
}) async {
  final notifier = ref.read(orderClaimProvider.notifier);
  notifier.setOrderRef(orderRef);
  if (isClaim) {
    await notifier.claim();
  } else {
    await notifier.unclaim();
  }
  if (!context.mounted) return;
  final claimState = ref.read(orderClaimProvider);
  showTopSnackBar(
    context,
    claimState.hasError
        ? (isClaim
            ? OrdersLabels.deliveryClaimFailed
            : OrdersLabels.deliveryUnclaimFailed)
        : (isClaim
            ? OrdersLabels.deliveryClaimSuccess
            : OrdersLabels.deliveryUnclaimSuccess),
  );
}