import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../providers/reconciliation_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'reconciliation_sell_waste_modal.dart';

class InlineWasteItem extends StatelessWidget {
  const InlineWasteItem({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.counted,
    required this.saleRows,
    required this.waste,
    required this.wasteReason,
    required this.notifier,
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

  @override
  Widget build(BuildContext context) {
    final reasonText = wasteReason.isEmpty ? '-' : wasteReason;
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
                  StockLabels.haoHutSheet,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${StockLabels.soLuongHaoHut}: $waste - ${StockLabels.lyDoHaoHut}: $reasonText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: StockLabels.sua,
            onPressed: () => showReconciliationWasteModal(
              context,
              product: product,
              option: option,
              optionKey: optionKey,
              counted: counted,
              saleRows: saleRows,
              waste: waste,
              wasteReason: wasteReason,
              notifier: notifier,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: OrdersLabels.xoa,
            onPressed: () {
              notifier.setWasteQty(optionKey, 0);
              notifier.setWasteReasonForOption(optionKey, '');
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}