import 'package:flutter/material.dart';

import '../../../data/models/order_draft.dart';
import '../../../shared/utils/order_helpers.dart';
import 'order_wizard.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class ProductSummaryCard extends StatelessWidget {
  const ProductSummaryCard({
    super.key,
    required this.items,
  });

  final List<DraftOrderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regularItems = items.where((i) => !i.isExtra).toList();
    final extraItems = items.where((i) => i.isExtra).toList();
    final total = regularItems.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );

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
              OrdersLabels.summaryProducts,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildRow(
              theme,
              VN.products,
              OrdersLabels.productCount(regularItems.length + extraItems.length),
            ),
            ...regularItems.map((item) => _buildItemRow(theme, item)),
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
        ),
      ),
    );
  }

  Widget _buildItemRow(ThemeData theme, DraftOrderItem item) {
    final cashAmount = int.tryParse(
      item.attributes['cash_amount']?.toString() ?? '',
    );
    final cashFee = int.tryParse(
      item.attributes['cash_fee']?.toString() ?? '',
    );
    final hasRutTien = item.attributes['rut_tien']?.toString() == 'true' &&
        cashAmount != null &&
        cashAmount > 0;

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.product.name} x${item.quantity} — ${formatVND(item.unitPrice * item.quantity)}',
            style: theme.textTheme.bodySmall,
          ),
          if (hasRutTien) ...[
            Text(
              '  ${VN.rutTien}: ${formatVND(cashAmount.toDouble())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (cashFee != null && cashFee > 0)
              Text(
                '  ${VN.phiRutTien}: ${formatVND(cashFee.toDouble())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ],
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
