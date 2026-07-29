import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/utils/launch_external_url.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../order_customer_section.dart';
import '../order_delivery_section.dart';
import '../section_header.dart';
import 'order_info_row.dart';

/// Order info block: customer, public code, source, due date, delivery
/// details, and created-by. Rendered between the status banner and the
/// items list.
class OrderInfoBlock extends StatelessWidget {
  const OrderInfoBlock({
    super.key,
    required this.order,
    required this.formatDueDisplay,
  });

  final Order order;
  final String Function(String? date, String? time) formatDueDisplay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(VN.customer),
        OrderInfoRow(
          icon: Icons.badge_outlined,
          label: VN.publicOrderCode,
          value: visualOrderCode(
            orderRef: order.orderRef,
            publicOrderCode: order.publicOrderCode,
          ),
        ),
        if (order.customerId != null)
          OrderCustomerSection(
            linkedCustomerId: order.customerId,
            mode: OrderCustomerSectionMode.readOnly,
          )
        else
          OrderCustomerSection(
            mode: OrderCustomerSectionMode.readOnly,
            customerName: order.customerName,
            customerPhone: order.customerPhone,
          ),
        if (order.source.isNotEmpty)
          OrderInfoRow(
            icon: Icons.campaign_outlined,
            label: VN.orderSource,
            value: order.source,
          ),
        if (order.dueDate != null)
          OrderInfoRow(
            icon: Icons.schedule_outlined,
            label: VN.dueDate,
            value: formatDueDisplay(order.dueDate, order.dueTime),
          ),
        OrderDeliverySection(
          deliveryType: order.deliveryType,
          deliveryAddress: order.deliveryAddress,
          customerPhone: order.customerPhone,
          deliveryPhone: order.deliveryPhone,
          shippingFee: order.shippingFee,
          notes: order.notes,
          latitude: order.latitude,
          longitude: order.longitude,
          googleMapsUrl: order.googleMapsUrl,
          onLaunchMap: () => launchExternalUrl(context, order.googleMapsUrl),
          mode: OrderDeliverySectionMode.readOnly,
        ),
        if (order.createdBy.isNotEmpty || order.createdStaffName.isNotEmpty)
          OrderInfoRow(
            icon: Icons.person_outline,
            label: 'Người tạo',
            value: order.displayCreatedBy,
          ),
      ],
    );
  }
}