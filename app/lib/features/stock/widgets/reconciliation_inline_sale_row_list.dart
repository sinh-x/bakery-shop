import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../providers/reconciliation_provider.dart';
import 'reconciliation_inline_sale_row_item.dart';

class InlineSaleRowList extends StatelessWidget {
  const InlineSaleRowList({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
          InlineSaleRowItem(
            key: ValueKey('$optionKey-inline-sale-row-$rowIndex'),
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
            rowIndex: rowIndex,
            row: saleRows[rowIndex],
          ),
      ],
    );
  }
}