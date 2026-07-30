import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/order_providers.dart';
import 'package:bakery_app/shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'widgets/google_maps_modal.dart';
import 'widgets/order_detail/order_detail_body.dart';
import 'widgets/order_detail/order_receipt_type_selector.dart';
import '../../data/models/order.dart';
import 'providers/delivery_claim_providers.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderRef));
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);

    List<PopupMenuEntry<String>> buildMenuItems(Order? order, CurrentStaff? staff, bool isClaiming) {
      final items = <PopupMenuEntry<String>>[];

      if (order != null) {
        items.addAll([
          const PopupMenuItem<String>(
            value: 'addIncident',
            child: Text(VN.addOrderIncident),
          ),
          const PopupMenuItem<String>(
            value: 'googleMaps',
            child: Text(OrdersLabels.googleMapsContextMenuLabel),
          ),
        ]);

        if (staff != null &&
            staff.canClaim &&
            isDeliveryType(order.deliveryType) &&
            activeOrderStatuses.contains(order.status)) {
          if (order.isAssigned) {
            if (staff.isAdmin || order.isClaimedBy(staff.staffIdAsString)) {
              items.add(const PopupMenuItem<String>(
                value: 'unclaim',
                child: Text(OrdersLabels.deliveryUnclaimButton),
              ));
            }
          } else {
            items.add(PopupMenuItem<String>(
              value: 'claim',
              child: Text(OrdersLabels.deliveryClaimButton),
              enabled: !isClaiming,
            ));
          }
        }
      }

      return items;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.orderDetail),
        actions: [
          if (orderAsync.asData != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: VN.editOrder,
              onPressed: () async {
                await context.push('/orders/$orderRef/edit');
                ref.read(orderDetailProvider(orderRef).notifier).refresh();
              },
            ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: VN.printReceipt,
            onPressed: () =>
                showOrderReceiptTypeSelector(context, ref, orderRef),
          ),
          AppBarOverflowMenu(
            items: buildMenuItems(
              orderAsync.asData?.value,
              staffAsync.asData?.value,
              claimAsync.isLoading,
            ),
            onSelected: (value) {
              if (value == 'addIncident') {
                final order = orderAsync.asData!.value;
                final orderId = int.tryParse(order.id);
                context.push(
                  '/orders/$orderRef/incident/new',
                  extra: orderId,
                );
              } else if (value == 'googleMaps') {
                final order = orderAsync.asData!.value;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => GoogleMapsModal(
                    orderRef: order.orderRef,
                    initialUrl: order.googleMapsUrl,
                  ),
                );
              } else if (value == 'claim' || value == 'unclaim') {
                _handleClaimMenuSelection(context, ref, value);
              }
            },
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(orderDetailProvider(orderRef).notifier).refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (order) => OrderDetailBody(order: order),
      ),
    );
  }

  /// Handles the "Nhận giao" / "Trả đơn" context menu selection: invokes the
  /// claim/unclaim API via [OrderClaimNotifier], then shows a success
  /// snackbar ("Đã nhận giao" / "Đã trả đơn") or an error snackbar on
  /// failure (FR1/FR2/AC1/AC2/AC3).
  Future<void> _handleClaimMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final notifier = ref.read(orderClaimProvider.notifier);
    notifier.setOrderRef(orderRef);
    final isClaim = value == 'claim';
    if (isClaim) {
      await notifier.claim();
    } else {
      await notifier.unclaim();
    }
    final claimState = ref.read(orderClaimProvider);
    if (claimState.hasError) {
      showTopSnackBar(
        context,
        isClaim
            ? OrdersLabels.deliveryClaimFailed
            : OrdersLabels.deliveryUnclaimFailed,
      );
      return;
    }
    showTopSnackBar(
      context,
      isClaim
          ? OrdersLabels.deliveryClaimSuccess
          : OrdersLabels.deliveryUnclaimSuccess,
    );
  }
}