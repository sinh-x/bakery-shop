import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../rut_tien_section.dart';
import 'order_work_item_section.dart';

/// Work Items tab content: full work item section (with status transitions
/// and internal-print prompts) plus the RutTien (cash withdrawal) section.
///
/// Both child widgets are reused as-is — they own their own provider watches
/// keyed by `orderRef` (NFR1: same already-loaded data, no network fetch on
/// tab switch). The shared `onRecordPayment` callback is forwarded from the
/// parent [OrderDetailScreen] so the payment sheet uses the same launcher as
/// the General tab.
class OrderDetailWorkItemsTab extends StatelessWidget {
  const OrderDetailWorkItemsTab({
    super.key,
    required this.order,
    required this.onRecordPayment,
  });

  final Order order;
  final void Function(double remaining) onRecordPayment;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OrderWorkItemSection(orderRef: order.orderRef, order: order),
        const SizedBox(height: 16),
        RutTienSection(
          orderRef: order.orderRef,
          onRecordPayment: onRecordPayment,
        ),
      ],
    );
  }
}