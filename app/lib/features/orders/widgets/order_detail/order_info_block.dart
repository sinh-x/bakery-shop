import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/utils/launch_external_url.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../../providers/delivery_claim_providers.dart';
import '../order_customer_section.dart';
import '../order_delivery_section.dart';
import '../section_header.dart';
import 'order_info_row.dart';

/// Order info block: customer, public code, source, due date, delivery
/// assignment, delivery details, and created-by. Rendered between the status
/// banner and the items list.
///
/// Watches [currentStaffProvider] and reacts to [orderDetailProvider] refresh
/// (via the [order] prop supplied by the parent [OrderDetailBody]) so the
/// delivery assignment row stays in sync after claim/unclaim (DG-311 / FR3 /
/// AC4).
class OrderInfoBlock extends ConsumerWidget {
  const OrderInfoBlock({
    super.key,
    required this.order,
    required this.formatDueDisplay,
  });

  final Order order;
  final String Function(String? date, String? time) formatDueDisplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch currentStaffProvider so the block rebuilds when staff context
    // changes (DG-311). The assignment row itself is derived from the order,
    // but keeping the provider in the widget graph ensures the detail screen
    // re-renders promptly after a claim/unclaim that mutates staff state.
    ref.watch(currentStaffProvider);

    final theme = Theme.of(context);
    final showAssignment = isDeliveryType(order.deliveryType);

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
        if (showAssignment) _buildAssignmentRow(theme),
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

  /// Delivery assignment row (FR3/AC4). Renders the assigned staff name with a
  /// person icon when the order is assigned, or "Chưa nhận" in italic when the
  /// delivery order is unassigned. Only rendered for delivery-type orders.
  Widget _buildAssignmentRow(ThemeData theme) {
    if (order.isAssigned && order.assignedStaffName.isNotEmpty) {
      return OrderInfoRow(
        icon: Icons.person_outline,
        label: VN.deliveryAssignee,
        value: order.assignedStaffName,
      );
    }
    return OrderInfoRow(
      icon: Icons.person_outline,
      label: VN.deliveryAssignee,
      value: OrdersLabels.deliveryUnassigned,
      valueStyle: theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.outline,
      ),
    );
  }
}