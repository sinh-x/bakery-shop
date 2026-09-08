import 'package:flutter/material.dart';

import '../../../../data/models/order_inventory_audit.dart';
import '../../../../shared/labels/stock.dart';
import '../../../../shared/utils/date_formatting.dart';

class OrderInventoryAuditEntryTile extends StatelessWidget {
  const OrderInventoryAuditEntryTile({super.key, required this.entry});

  final OrderInventoryAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final product = [
      entry.item.productName,
      entry.item.productCode,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return ExpansionTile(
      key: ValueKey('inventory-audit-entry-${entry.id}'),
      leading: Icon(_outcomeIcon(entry.outcome)),
      title: Text(StockLabels.inventoryAuditActionLabel(entry.action)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(
              StockLabels.inventoryAuditTime,
              formatDisplay(entry.createdAt),
            ),
            _line(StockLabels.inventoryAuditActor, entry.actor.displayName),
            _line(
              StockLabels.inventoryAuditOutcome,
              StockLabels.inventoryAuditOutcomeLabel(entry.outcome),
            ),
            _line(
              StockLabels.inventoryAuditProduct,
              product.isEmpty ? StockLabels.inventoryAuditUnknown : product,
            ),
            _line(
              StockLabels.inventoryAuditPriceChip,
              entry.item.chipLabel ?? StockLabels.inventoryAuditNone,
            ),
            _line(
              StockLabels.inventoryAuditRequestedDelta,
              _quantity(entry.requestedDelta),
            ),
            _line(
              StockLabels.inventoryAuditAppliedDelta,
              _quantity(entry.appliedDelta),
            ),
            _line(
              StockLabels.inventoryAuditBeforeNet,
              _quantity(entry.before.net),
            ),
            _line(
              StockLabels.inventoryAuditAfterNet,
              _quantity(entry.after.net),
            ),
            _line(
              StockLabels.inventoryAuditReason,
              StockLabels.inventoryAuditReasonLabel(entry.reasonCode),
            ),
          ],
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const Divider(),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            StockLabels.inventoryAuditDetails,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        _snapshot(StockLabels.inventoryAuditBefore, entry.before),
        _snapshot(StockLabels.inventoryAuditAfter, entry.after),
        const Divider(),
        _line(StockLabels.inventoryAuditEntryId, entry.id.toString()),
        _line(StockLabels.inventoryAuditOperationId, entry.operationId),
        _line(
          StockLabels.inventoryAuditOrderItemId,
          _identifier(entry.item.orderItemId),
        ),
        _line(
          StockLabels.inventoryAuditProductId,
          _identifier(entry.item.productId),
        ),
        _line(
          StockLabels.inventoryAuditStockMovementId,
          _identifier(entry.stockMovementId),
        ),
        _line(
          StockLabels.inventoryAuditNegativeMovementId,
          _identifier(entry.negativeMovementId),
        ),
        _line(
          StockLabels.inventoryAuditRelatedEntryId,
          _identifier(entry.relatedEntryId),
        ),
        _line(
          StockLabels.inventoryAuditReconciliationSessionIds,
          _identifiers(entry.reconciliationSessionIds),
        ),
        _line(
          StockLabels.inventoryAuditReconciliationLineIds,
          _identifiers(entry.reconciliationLineIds),
        ),
        _line(
          StockLabels.inventoryAuditReconciliationSaleRowIds,
          _identifiers(entry.reconciliationSaleRowIds),
        ),
      ],
    );
  }
}

Widget _snapshot(String label, OrderInventorySnapshot snapshot) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      _line(StockLabels.inventoryAuditFifo, _quantity(snapshot.fifoAvailable)),
      _line(StockLabels.inventoryAuditNegative, _quantity(snapshot.negative)),
      _line(StockLabels.inventoryAuditNet, _quantity(snapshot.net)),
    ],
  ),
);

Widget _line(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 1),
  child: Text('$label: $value'),
);

String _quantity(int? value) {
  if (value == null) return StockLabels.inventoryAuditNone;
  return value > 0 ? '+$value' : value.toString();
}

String _identifier(int? value) =>
    value?.toString() ?? StockLabels.inventoryAuditNone;

String _identifiers(List<int> values) =>
    values.isEmpty ? StockLabels.inventoryAuditNone : values.join(', ');

IconData _outcomeIcon(String outcome) => switch (outcome) {
  'applied' => Icons.check_circle_outline,
  'reversed' => Icons.undo,
  'failed' => Icons.error_outline,
  'skipped' => Icons.skip_next_outlined,
  _ => Icons.remove_circle_outline,
};
