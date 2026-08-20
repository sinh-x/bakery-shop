import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../providers/reconciliation_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'reconciliation_inline_sale_row_list.dart';
import 'reconciliation_inline_waste_item.dart';
import 'reconciliation_sell_waste_modal.dart';
import 'reconciliation_shared_widgets.dart';
import 'reconciliation_surplus_indicator.dart';
import 'reconciliation_variance_indicator.dart';

class ReconciliationOptionEditor extends ConsumerWidget {
  const ReconciliationOptionEditor({
    required this.product,
    required this.option,
    required this.countedController,
    required this.syncIntController,
    required this.notifier,
    super.key,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final TextEditingController countedController;
  final void Function(TextEditingController controller, int value)
      syncIntController;
  final ReconciliationNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reconciliationProvider);
    final optionKey = reconciliationOptionKey(
      product.productId,
      option.normalizedPrice,
      discriminator: option.keyDiscriminator,
    );
    final counted = state.countedQtyByOption[optionKey] ?? option.defaultCountedQty;
    final saleRows =
        state.saleRowsByOption[optionKey] ??
        const <ReconciliationSaleRowInput>[];
    final waste = state.wasteQtyByOption[optionKey] ?? 0;
    final wasteReason = state.wasteReasonByOption[optionKey] ?? '';
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final variance = option.expectedQty - counted - saleQty - waste;
    final surplus = state.surplusQtyFor(
      optionKey,
      option.expectedQty,
      grossAvailableQty: option.grossAvailableQty,
    );
    final optionError = state.optionErrors[optionKey];

    syncIntController(countedController, counted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReconciliationQuantityStepperField(
          label: StockLabels.tonDaDem,
          controller: countedController,
          onChanged: (value) => notifier.setCountedQty(optionKey, value),
          onDecrement: () {
            if (counted <= 0) {
              return;
            }
            notifier.setCountedQty(optionKey, counted - 1);
          },
          onIncrement: () => notifier.setCountedQty(optionKey, counted + 1),
        ),
        if (surplus > 0) ...[
          const SizedBox(height: 8),
          ReconciliationSurplusIndicator(surplus: surplus),
          const SizedBox(height: 4),
          Text(
            StockLabels.nhapBuHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.teal[700],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
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
              ),
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text(OrdersLabels.banHang),
            ),
            OutlinedButton.icon(
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
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text(StockLabels.haoHutSheet),
            ),
            ReconciliationVarianceIndicator(variance: variance),
          ],
        ),
        if (saleRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          InlineSaleRowList(
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
          ),
        ],
        if (waste > 0 || wasteReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          InlineWasteItem(
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
          ),
        ],
        if (optionError != null) ...[
          const SizedBox(height: 8),
          Text(
            optionError,
            style: TextStyle(
              color: Colors.red[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}