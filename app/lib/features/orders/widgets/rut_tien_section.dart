import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order_providers.dart';
import '../../../data/models/work_item.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'section_header.dart';

class RutTienSection extends ConsumerWidget {
  const RutTienSection({
    super.key,
    required this.orderRef,
    this.onRecordPayment,
  });

  final String orderRef;
  final void Function(double remaining)? onRecordPayment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(orderWorkItemsProvider(orderRef));
    final txnsAsync = ref.watch(orderPaymentTransactionsProvider(orderRef));
    final items = itemsAsync.value ?? [];
    final txns = txnsAsync.value ?? [];
    final rutTienItems = items
        .where(
          (i) =>
              i.attributes['rut_tien']?.toString() == 'true' ||
              i.attributes['rut_tien'] == true,
        )
        .toList();

    if (rutTienItems.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final totalTarget = rutTienItems.fold<int>(0, (sum, item) {
      return sum +
          (int.tryParse(item.attributes['cash_amount']?.toString() ?? '') ?? 0);
    });
    final totalReceived = txns
        .where((t) => t.type == 'tien_rut')
        .fold<double>(0, (sum, t) => sum + t.amount);
    final remaining = totalTarget.toDouble() - totalReceived;
    final isFullyReceived = totalReceived >= totalTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(VN.rutTienSection),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in rutTienItems) ...[_RutTienItemRow(item: item)],
              const Divider(height: 16),
              Row(
                children: [
                  Icon(
                    isFullyReceived ? Icons.check_circle : Icons.pending,
                    color: isFullyReceived
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tiền khách đưa: ${formatVND(totalReceived)} / ${formatVND(totalTarget.toDouble())}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isFullyReceived
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (remaining > 0 && onRecordPayment != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onRecordPayment!(remaining),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('+ Khách đưa tiền rút'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber.shade800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RutTienItemRow extends StatelessWidget {
  const _RutTienItemRow({required this.item});

  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cashAmount =
        int.tryParse(item.attributes['cash_amount']?.toString() ?? '') ?? 0;
    final cashFee =
        int.tryParse(item.attributes['cash_fee']?.toString() ?? '') ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.productName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (cashAmount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '${VN.soTienRut}: ${formatVND(cashAmount.toDouble())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.green.shade700,
                ),
              ),
            ),
          if (cashFee > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '${VN.phiRutTien}: ${formatVND(cashFee.toDouble())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.green.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
