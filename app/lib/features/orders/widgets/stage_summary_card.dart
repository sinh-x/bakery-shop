import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../shared/utils/order_helpers.dart';
import 'order_wizard.dart';
import 'package:bakery_app/shared/labels/orders.dart';
export 'product_summary_card.dart' show ProductSummaryCard;

class CustomerSummaryCard extends StatelessWidget {
  const CustomerSummaryCard({
    super.key,
    required this.wizardData,
    required this.source,
  });

  final OrderWizardData wizardData;
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = wizardData;

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
              OrdersLabels.summaryCustomer,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildRow(
              theme,
              OrdersLabels.customerName,
              data.customerName.isNotEmpty ? data.customerName : '—',
            ),
            if (data.customerPhone.isNotEmpty)
              _buildRow(theme, OrdersLabels.customerPhone, data.customerPhone),
            _buildRow(
              theme,
              OrdersLabels.orderSource,
              source.isNotEmpty ? source : '—',
            ),
          ],
        ),
      ),
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

class DeliverySummaryCard extends StatelessWidget {
  const DeliverySummaryCard({
    super.key,
    required this.wizardData,
    this.dueDate,
    this.dueTime,
  });

  final OrderWizardData wizardData;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = wizardData;
    final dateStr = dueDate != null
        ? '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
        : '—';
    final timeStr = dueTime != null
        ? '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}'
        : '—';

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
              OrdersLabels.summaryDelivery,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildRow(theme, OrdersLabels.deliveryType, deliveryTypeLabel(data.deliveryType)),
            if (data.needsAddress) ...[
              if (data.deliveryPhone.isNotEmpty)
                _buildRow(theme, OrdersLabels.deliveryPhone, data.deliveryPhone),
              if (data.deliveryAddress.isNotEmpty)
                _buildRow(theme, OrdersLabels.deliveryAddress, data.deliveryAddress),
            ],
            if (data.deliveryType == 'bus' || data.deliveryType == 'door')
              _buildRow(
                theme,
                OrdersLabels.shippingFee,
                data.shippingFee > 0
                    ? formatVND(data.shippingFee)
                    : OrdersLabels.shippingFree,
              ),
            if (data.notes.isNotEmpty) _buildRow(theme, OrdersLabels.notes, data.notes),
            _buildRow(theme, OrdersLabels.dueDate, '$dateStr — $timeStr'),
          ],
        ),
      ),
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
