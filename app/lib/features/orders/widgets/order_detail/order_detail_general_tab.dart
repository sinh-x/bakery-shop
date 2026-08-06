import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/models/enum_attribute.dart';
import '../../../../data/models/order.dart';
import '../../../../data/models/product.dart';
import '../../../../providers/products_provider.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import '../order_photo_section.dart';
import 'order_info_block.dart';
import 'order_items_list.dart';
import 'order_payment_status_summary.dart';
import 'order_payment_summary.dart';
import 'order_print_status_row.dart';
import 'order_work_item_summary.dart';

/// General tab content: order info block, items list, payment summary, print
/// status row, and photo section. Work item / transaction sections live on
/// their dedicated tabs; this tab shows summary counts only (Phase 3 adds
/// the work item summary count and payment status summary).
///
/// Receives the already-computed payment snapshot (`amountPaid`, `remaining`,
/// `paymentColor`, `paymentLabel`) and shared action callbacks from the
/// parent [OrderDetailScreen] so no provider recomputation is needed when
/// switching tabs (NFR1).
class OrderDetailGeneralTab extends ConsumerWidget {
  const OrderDetailGeneralTab({
    super.key,
    required this.order,
    required this.amountPaid,
    required this.remaining,
    required this.paymentColor,
    required this.paymentLabel,
    required this.onAddPayment,
    required this.onMarkAsPrinted,
    required this.onUnmarkPrinted,
  });

  final Order order;
  final double amountPaid;
  final double remaining;
  final Color paymentColor;
  final String paymentLabel;
  final VoidCallback onAddPayment;
  final VoidCallback onMarkAsPrinted;
  final VoidCallback onUnmarkPrinted;

  String _formatDueDisplay(String? date, String? time) {
    if (date == null) return '—';
    final d = parseApiDate(date);
    if (d == null) return time != null ? '$date $time' : date;
    final dateStr = formatDisplayDate(d);
    return time != null ? '$dateStr $time' : dateStr;
  }

  List<EnumAttribute> _enumAttributesFor(
    String productId,
    List<Product> products,
  ) {
    if (productId.isEmpty || products.isEmpty) return const [];
    for (final p in products) {
      if (p.id.toString() == productId || p.productCode == productId) {
        return p.enumAttributes;
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).asData?.value ?? const [];
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OrderPrintStatusRow(
          printedAt: order.workTicketPrintedAt,
          onMarkPrinted: onMarkAsPrinted,
          onUnmarkPrinted: onUnmarkPrinted,
        ),
        OrderInfoBlock(order: order, formatDueDisplay: _formatDueDisplay),
        const SizedBox(height: 16),
        OrderItemsList(
          order: order,
          enumAttributesFor: (id) => _enumAttributesFor(id, products),
        ),
        OrderPaymentSummary(
          order: order,
          amountPaid: amountPaid,
          remaining: remaining,
          paymentColor: paymentColor,
          paymentLabel: paymentLabel,
          onAddPayment: onAddPayment,
        ),
        const SizedBox(height: 16),
        OrderWorkItemSummary(orderRef: order.orderRef),
        const SizedBox(height: 16),
        OrderPaymentStatusSummary(
          order: order,
          amountPaid: amountPaid,
          paymentColor: paymentColor,
        ),
        const SizedBox(height: 16),
        OrderPhotoSection(orderRef: order.orderRef, baseUrl: baseUrl),
      ],
    );
  }
}