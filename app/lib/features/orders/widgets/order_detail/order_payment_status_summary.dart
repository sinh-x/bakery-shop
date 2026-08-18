import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Summary overview widget for the General tab (Phase 3 — DG-334 / FR4 / AC4).
///
/// Renders a compact paid-vs-total line, e.g.
/// "Đã thanh toán: 500.000đ / 750.000đ". This is a *summary* only — the full
/// payment breakdown lives in `OrderPaymentSummary` below it and the
/// transaction history lives on the Transactions tab.
///
/// Receives the already-computed `amountPaid` from the parent
/// [OrderDetailGeneralTab] so no provider recomputation is needed when
/// switching tabs (NFR1).
class OrderPaymentStatusSummary extends StatelessWidget {
  const OrderPaymentStatusSummary({
    super.key,
    required this.order,
    required this.amountPaid,
    required this.paymentColor,
  });

  final Order order;
  final double amountPaid;
  final Color paymentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = order.totalPrice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(OrdersLabels.paymentStatusSummaryTitle),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: paymentColor.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: paymentColor.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  OrdersLabels.paid,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatVND(amountPaid),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: amountPaid > 0 ? paymentColor : null,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: ' ${OrdersLabels.paymentStatusSummaryOfTotal} ${formatVND(total)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}