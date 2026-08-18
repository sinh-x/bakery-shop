import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/api/receipt_service.dart';
import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Bottom sheet that lets staff pick which receipt type to print for an order.
class OrderReceiptTypeSelector extends ConsumerWidget {
  const OrderReceiptTypeSelector({super.key, required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.read(orderWorkItemsProvider(orderRef)).value ?? [];
    final mainItems = allItems.where((i) => !i.isExtra).toList();
    final order = ref.read(orderDetailProvider(orderRef)).value;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              VN.selectReceiptType,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (mainItems.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.receipt),
              title: const Text(VN.printWorkTicket),
              onTap: () {
                Navigator.pop(context);
                if (mainItems.length == 1) {
                  context.push(
                    '/orders/$orderRef/receipt?type=${ReceiptType.workTicket.value}&item_id=${mainItems.first.id}',
                  );
                } else {
                  _showItemPicker(context, mainItems);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text(VN.printCustomerReceipt),
            onTap: () {
              Navigator.pop(context);
              context.push(
                '/orders/$orderRef/receipt?type=${ReceiptType.customer.value}',
              );
            },
          ),
          if (order?.deliveryType == 'bus')
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text(VN.printBusLabel),
              onTap: () {
                Navigator.pop(context);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.busLabel.value}',
                );
              },
            ),
          if (order?.deliveryType == 'pickup')
            ListTile(
              leading: const Icon(Icons.store),
              title: const Text(VN.printShopReceipt),
              onTap: () {
                Navigator.pop(context);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.shop.value}',
                );
              },
            ),
          if (order?.deliveryType == 'door')
            ListTile(
              leading: const Icon(Icons.delivery_dining),
              title: const Text(VN.printDeliveryReceipt),
              onTap: () {
                Navigator.pop(context);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.delivery.value}',
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showItemPicker(BuildContext context, List<WorkItem> items) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chọn sản phẩm',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final item in items)
              ListTile(
                leading: const Icon(Icons.cake_outlined),
                title: Text(item.productName),
                subtitle: Text('SL: ${item.quantity}'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/orders/$orderRef/receipt?type=${ReceiptType.workTicket.value}&item_id=${item.id}',
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Shows the receipt type selector as a modal bottom sheet.
void showOrderReceiptTypeSelector(
  BuildContext context,
  WidgetRef ref,
  String orderRef,
) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => OrderReceiptTypeSelector(orderRef: orderRef),
  );
}