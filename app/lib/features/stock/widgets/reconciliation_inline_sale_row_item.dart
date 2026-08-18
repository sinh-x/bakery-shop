import 'package:bakery_app/shared/utils.dart' show formatVND, paymentMethodLabel;
import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../providers/reconciliation_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'reconciliation_sell_waste_modal.dart';

class InlineSaleRowItem extends StatelessWidget {
  const InlineSaleRowItem({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.counted,
    required this.saleRows,
    required this.waste,
    required this.wasteReason,
    required this.notifier,
    required this.rowIndex,
    required this.row,
    super.key,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int counted;
  final List<ReconciliationSaleRowInput> saleRows;
  final int waste;
  final String wasteReason;
  final ReconciliationNotifier notifier;
  final int rowIndex;
  final ReconciliationSaleRowInput row;

  @override
  Widget build(BuildContext context) {
    final priceText = row.unitPrice == null
        ? '-'
        : formatVND(row.unitPrice!.toDouble());
    final methodText = row.paymentMethod == null || row.paymentMethod!.isEmpty
        ? '-'
        : paymentMethodLabel(row.paymentMethod!);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${StockLabels.dongBan} ${rowIndex + 1}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${StockLabels.soLuongBan}: ${row.quantity} - $priceText - $methodText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: StockLabels.sua,
            onPressed: () => showReconciliationSaleModal(
              context,
              product: product,
              option: option,
              optionKey: optionKey,
              counted: counted,
              saleRows: saleRows,
              waste: waste,
              wasteReason: wasteReason,
              notifier: notifier,
              editingRowIndex: rowIndex,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: OrdersLabels.xoa,
            onPressed: () => notifier.removeSaleRow(optionKey, rowIndex),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}