import 'dart:async';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/staff_service.dart';
import '../../../../data/models/order.dart';
import '../../../../data/providers/order/order_detail_notifier.dart';
import '../../../../data/providers/staff_provider.dart';
import 'package:bakery_app/shared/utils/launch_external_url.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../../providers/delivery_claim_providers.dart';
import '../../providers/order_info_block_notifier.dart';
import 'delivery_claim_inline_actions.dart';
import '../../../orders/widgets/order_edit/staff_assignment_dropdown.dart';
import '../order_customer_section.dart';
import '../order_delivery_section.dart';
import '../section_header.dart';
import 'order_info_row.dart';
/// Order info block: customer, public code, source, due date, delivery
/// assignment, delivery details, and created-by. Rendered between the status
/// banner and the items list.
///
/// Watches [currentStaffProvider] and reacts to [orderDetailProvider] refresh
/// (via the [order] prop supplied by the parent screen/tab widget) so the
/// delivery assignment row stays in sync after claim/unclaim (DG-311 / FR3 /
/// AC4).
///
/// DG-304 Phase 5: for admins, the delivery assignment row is replaced with
/// an editable [StaffAssignmentDropdown] that persists the change via
/// `PATCH /api/orders/{ref}` and logs it in `order_history` (FR9/AC5). For
/// non-admins the static display row is preserved.
class OrderInfoBlock extends ConsumerStatefulWidget {
  const OrderInfoBlock({
    super.key,
    required this.order,
    required this.formatDueDisplay,
  });

  final Order order;
  final String Function(String? date, String? time) formatDueDisplay;

  @override
  ConsumerState<OrderInfoBlock> createState() => _OrderInfoBlockState();
}

class _OrderInfoBlockState extends ConsumerState<OrderInfoBlock> {
  @override
  void didUpdateWidget(covariant OrderInfoBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the local selection in sync with the authoritative order prop
    // (e.g. after a successful PATCH refresh or external claim/unclaim).
    if (oldWidget.order.assignedStaffId != widget.order.assignedStaffId) {
      ref
          .read(orderInfoBlockProvider.notifier)
          .syncFromOrder(widget.order.assignedStaffId);
    }
  }

  Future<void> _onAssignedStaffChanged(String? staffId) async {
    final notifier = ref.read(orderInfoBlockProvider.notifier);
    final current = ref.read(orderInfoBlockProvider);
    if (staffId == current.selectedStaffId || current.savingAssignment) return;
    notifier.startSave(staffId);
    try {
      await ref
          .read(orderDetailProvider(widget.order.orderRef).notifier)
          .saveAssignedStaff(staffId);
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.assignStaffSaved);
      }
    } catch (_) {
      // Revert the local selection on failure so the dropdown reflects the
      // authoritative server state (the order prop will refresh on rebuild).
      if (mounted) {
        notifier.revert(widget.order.assignedStaffId);
        showTopSnackBar(
          context,
          OrdersLabels.assignStaffSaveFailed,
          backgroundColor: Colors.red.shade800,
        );
      }
    } finally {
      if (mounted) notifier.finishSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch currentStaffProvider so the block rebuilds when staff context
    // changes (DG-311). The assignment row itself is derived from the order,
    // but keeping the provider in the widget graph ensures the detail screen
    // re-renders promptly after a claim/unclaim that mutates staff state.
    final staffAsync = ref.watch(currentStaffProvider);
    final theme = Theme.of(context);
    final showAssignment = isDeliveryType(widget.order.deliveryType);
    final isAdmin = staffAsync.asData?.value.isAdmin ?? false;
    final blockState = ref.watch(orderInfoBlockProvider);
    // The local selection lags the order prop only during the PATCH
    // round-trip; otherwise prefer the authoritative order value.
    final selectedStaffId = blockState.savingAssignment
        ? blockState.selectedStaffId
        : widget.order.assignedStaffId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(OrdersLabels.customer),
        OrderInfoRow(
          icon: Icons.badge_outlined,
          label: OrdersLabels.publicOrderCode,
          value: visualOrderCode(
            orderRef: widget.order.orderRef,
            publicOrderCode: widget.order.publicOrderCode,
          ),
        ),
        if (widget.order.customerId != null)
          OrderCustomerSection(
            linkedCustomerId: widget.order.customerId,
            mode: OrderCustomerSectionMode.readOnly,
          )
        else
          OrderCustomerSection(
            mode: OrderCustomerSectionMode.readOnly,
            customerName: widget.order.customerName,
            customerPhone: widget.order.customerPhone,
          ),
        if (widget.order.source.isNotEmpty)
          OrderInfoRow(
            icon: Icons.campaign_outlined,
            label: OrdersLabels.orderSource,
            value: widget.order.source,
          ),
        if (widget.order.dueDate != null)
          OrderInfoRow(
            icon: Icons.schedule_outlined,
            label: OrdersLabels.dueDate,
            value: widget.formatDueDisplay(
              widget.order.dueDate,
              widget.order.dueTime,
            ),
          ),
        if (showAssignment) ...[
          isAdmin
              ? _buildEditableAssignmentRow(selectedStaffId)
              : _buildStaticAssignmentRow(theme, ref),
          // DG-329 Phase 6 / FR7 / AC6: claim/unclaim button renders directly
          // below the "Nhân viên giao hàng" assignment row, inside the
          // OrderInfoBlock — not below the entire block. Reuses the existing
          // DeliveryClaimInlineActions widget verbatim; only repositioned.
          DeliveryClaimInlineActions(order: widget.order),
        ],
        OrderDeliverySection(
          deliveryType: widget.order.deliveryType,
          deliveryAddress: widget.order.deliveryAddress,
          customerPhone: widget.order.customerPhone,
          deliveryPhone: widget.order.deliveryPhone,
          shippingFee: widget.order.shippingFee,
          notes: widget.order.notes,
          latitude: widget.order.latitude,
          longitude: widget.order.longitude,
          googleMapsUrl: widget.order.googleMapsUrl,
          onLaunchMap: () =>
              launchExternalUrl(context, widget.order.googleMapsUrl),
          mode: OrderDeliverySectionMode.readOnly,
        ),
        if (widget.order.createdBy.isNotEmpty ||
            widget.order.createdStaffName.isNotEmpty)
          OrderInfoRow(
            icon: Icons.person_outline,
            label: 'Người tạo',
            value: widget.order.displayCreatedBy,
          ),
      ],
    );
  }

  /// Editable staff assignment dropdown for admins (FR9/AC5). Persists the
  /// selection via `PATCH /api/orders/{ref}` (FR7) and logs the change in
  /// `order_history`.
  Widget _buildEditableAssignmentRow(String? selectedStaffId) {
    final savingAssignment = ref.watch(orderInfoBlockProvider).savingAssignment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StaffAssignmentDropdown(
        assignedStaffId: selectedStaffId,
        onChanged: savingAssignment ? null : _onAssignedStaffChanged,
      ),
    );
  }

  /// Static delivery assignment row for non-admins (FR3/AC4). Renders the
  /// assigned staff name with a person icon when the order is assigned, or
  /// "Chưa nhận" in italic when the delivery order is unassigned. Only
  /// rendered for delivery-type orders.
  ///
  /// DG-329 Phase 2 / FR3 / AC2: resolves the assigned staff display name
  /// via [resolveAssignedStaffDisplayName] so the real name shows. When the
  /// staff record is missing entirely (deleted), the "NV #`<id>`" fallback
  /// is shown instead of the misleading "Chưa nhận" label for an assigned
  /// order.
  Widget _buildStaticAssignmentRow(ThemeData theme, WidgetRef ref) {
    if (widget.order.isAssigned) {
      final allStaff = ref.watch(staffListProvider).maybeWhen(
            data: (list) => list,
            orElse: () => const <StaffMember>[],
          );
      final displayName = resolveAssignedStaffDisplayName(
        assignedStaffId: widget.order.assignedStaffId,
        assignedStaffName: widget.order.assignedStaffName,
        staffList: allStaff,
      );
      if (displayName != null) {
        return OrderInfoRow(
          icon: Icons.person_outline,
          label: OrdersLabels.deliveryAssignee,
          value: displayName,
        );
      }
    }
    return OrderInfoRow(
      icon: Icons.person_outline,
      label: OrdersLabels.deliveryAssignee,
      value: OrdersLabels.deliveryUnassigned,
      valueStyle: theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.outline,
      ),
    );
  }
}