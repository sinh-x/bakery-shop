import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/order_providers.dart';
import 'package:bakery_app/shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'widgets/google_maps_modal.dart';
import 'widgets/order_detail/order_detail_body.dart';
import 'widgets/order_detail/order_receipt_type_selector.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderRef));

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
            items: orderAsync.asData != null
                ? [
                    const PopupMenuItem<String>(
                      value: 'addIncident',
                      child: Text(VN.addOrderIncident),
                    ),
                    const PopupMenuItem<String>(
                      value: 'googleMaps',
                      child: Text(OrdersLabels.googleMapsContextMenuLabel),
                    ),
                  ]
                : [],
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
}