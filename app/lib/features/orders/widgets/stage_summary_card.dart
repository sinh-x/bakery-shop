import 'package:flutter/material.dart';

import '../../../data/models/order_draft.dart';
import '../../../shared/utils/order_helpers.dart';
import 'order_wizard.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Compact summary card displaying info entered in previous wizard stages.
///
/// Used by Stage 2 (showing Stage 1 product info), Stage 3 (showing Stages 1-2),
/// and Stage 4 (showing Stages 1-3) so the user always sees a recap of
/// earlier choices below the current input area (DG-211 Phase 4, FR7, AC7).
class StageSummaryCard extends StatelessWidget {
  const StageSummaryCard({
    super.key,
    required this.items,
    required this.wizardData,
    this.source = '',
    this.dueDate,
    this.dueTime,
    this.showProducts = false,
    this.showCustomer = false,
    this.showDelivery = false,
  });

  final List<DraftOrderItem> items;
  final OrderWizardData wizardData;
  final String source;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;

  /// Whether to render the Stage 1 (products) section.
  final bool showProducts;

  /// Whether to render the Stage 2 (customer) section.
  final bool showCustomer;

  /// Whether to render the Stage 3 (delivery) section.
  final bool showDelivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[];

    if (showProducts) {
      sections.add(_buildProductsSection(theme));
    }
    if (showCustomer) {
      sections.add(_buildCustomerSection(theme));
    }
    if (showDelivery) {
      sections.add(_buildDeliverySection(theme));
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              OrdersLabels.previousStagesSummary,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...sections,
          ],
        ),
      ),
    );
  }

  Widget _buildProductsSection(ThemeData theme) {
    final regularItems = items.where((i) => !i.isExtra).toList();
    final extraItems = items.where((i) => i.isExtra).toList();
    final total = regularItems.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(OrdersLabels.stage1Label),
        _buildRow(
          theme,
          VN.products,
          OrdersLabels.productCount(regularItems.length + extraItems.length),
        ),
        ...regularItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 2),
            child: Text(
              '${item.product.name} x${item.quantity} — ${formatVND(item.unitPrice * item.quantity)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        if (extraItems.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildRow(theme, VN.extras, OrdersLabels.extraCount(extraItems.length)),
          ...extraItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 2),
              child: Text(
                '${item.product.name} x${item.quantity}${item.isGift ? ' (${VN.tangKem})' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
        _buildRow(theme, VN.total, formatVND(total)),
      ],
    );
  }

  Widget _buildCustomerSection(ThemeData theme) {
    final data = wizardData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const SectionHeader(OrdersLabels.stage2Label),
        _buildRow(
          theme,
          VN.customerName,
          data.customerName.isNotEmpty ? data.customerName : '—',
        ),
        if (data.customerPhone.isNotEmpty)
          _buildRow(theme, VN.customerPhone, data.customerPhone),
        _buildRow(
          theme,
          VN.orderSource,
          source.isNotEmpty ? source : '—',
        ),
      ],
    );
  }

  Widget _buildDeliverySection(ThemeData theme) {
    final data = wizardData;
    final dateStr = dueDate != null
        ? '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
        : '—';
    final timeStr = dueTime != null
        ? '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const SectionHeader(OrdersLabels.stage3Label),
        _buildRow(theme, VN.deliveryType, deliveryTypeLabel(data.deliveryType)),
        if (data.needsAddress) ...[
          if (data.deliveryPhone.isNotEmpty)
            _buildRow(theme, OrdersLabels.deliveryPhone, data.deliveryPhone),
          if (data.deliveryAddress.isNotEmpty)
            _buildRow(theme, VN.deliveryAddress, data.deliveryAddress),
        ],
        if (data.deliveryType == 'bus' || data.deliveryType == 'door')
          _buildRow(
            theme,
            VN.shippingFee,
            data.shippingFee > 0
                ? formatVND(data.shippingFee)
                : VN.shippingFree,
          ),
        if (data.notes.isNotEmpty) _buildRow(theme, VN.notes, data.notes),
        _buildRow(theme, VN.dueDate, '$dateStr — $timeStr'),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}