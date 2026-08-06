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
import 'providers/delivery_claim_handler.dart';
import 'providers/delivery_claim_providers.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<PopupMenuEntry<String>> buildMenuItems(
    Order? order,
    CurrentStaff? staff,
    bool isClaiming,
  ) {
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
            enabled: !isClaiming,
            child: const Text(OrdersLabels.deliveryClaimButton),
          ));
        }
      }
    }

    return items;
  }

  /// Handles the "Nhận giao" / "Trả đơn" context menu selection: delegates to
  /// the shared [handleDeliveryClaimAction] helper so the context menu uses
  /// the same claim/unclaim code path as [DeliveryClaimActions] and
  /// [DeliveryClaimInlineActions] (DG-311 Phase 4 / FR5 / AC7).
  Future<void> _handleClaimMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) =>
      handleDeliveryClaimAction(
        context,
        ref,
        widget.orderRef,
        isClaim: value == 'claim',
      );

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderRef));
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.orderDetail),
        actions: [
          if (orderAsync.asData != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: VN.editOrder,
              onPressed: () async {
                await context.push('/orders/${widget.orderRef}/edit');
                ref
                    .read(orderDetailProvider(widget.orderRef).notifier)
                    .refresh();
              },
            ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: VN.printReceipt,
            onPressed: () => showOrderReceiptTypeSelector(
              context,
              ref,
              widget.orderRef,
            ),
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
                  '/orders/${widget.orderRef}/incident/new',
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: VN.orderDetailTabGeneral),
            Tab(text: VN.orderDetailTabWorkItems),
            Tab(text: VN.orderDetailTabTransactions),
          ],
        ),
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
                onPressed: () => ref
                    .read(orderDetailProvider(widget.orderRef).notifier)
                    .refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (order) => TabBarView(
          controller: _tabController,
          children: [
            // ── Tab 0: General ───────────────────────────────────────────
            // Phase 1: shows current full body content. Phase 2 will split
            // General/Work Items/Transactions tab content.
            OrderDetailBody(order: order),
            // ── Tab 1: Work Items (placeholder — Phase 2) ─────────────────
            const Center(child: Text(VN.orderDetailTabWorkItems)),
            // ── Tab 2: Transactions (placeholder — Phase 2) ───────────────
            const Center(child: Text(VN.orderDetailTabTransactions)),
          ],
        ),
      ),
    );
  }
}