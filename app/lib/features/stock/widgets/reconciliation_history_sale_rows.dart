import 'package:bakery_app/shared/utils.dart' show formatVND, paymentMethodLabel;
import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';
/// Collapsible sale-rows section rendered inside an expanded
/// [ReconciliationHistoryLineCard]. The section header shows the sale-row
/// count and toggles the list of [ReconciliationHistorySaleRow] items.
class ReconciliationHistorySaleRowsSection extends StatelessWidget {
  const ReconciliationHistorySaleRowsSection({
    required this.saleRows,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final List<ReconciliationHistorySaleRow> saleRows;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${StockLabels.soDongBan}: ${saleRows.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (expanded)
          for (var i = 0; i < saleRows.length; i++)
            ReconciliationHistorySaleRowView(row: saleRows[i], index: i),
      ],
    );
  }
}

class ReconciliationHistorySaleRowView extends StatelessWidget {
  const ReconciliationHistorySaleRowView({required this.row, required this.index, super.key});

  final ReconciliationHistorySaleRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title = row.isLegacy
        ? '${index + 1}. ${StockLabels.dongBanCu}'
        : '${index + 1}. ${StockLabels.dongBan}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('${StockLabels.soLuongBan}: ${row.quantity}'),
          Text(
            '${OrdersLabels.donGia}: ${row.unitPrice != null ? formatVND(row.unitPrice!) : StockLabels.khongCo}',
          ),
          Text(
            '${StockLabels.phuongThucThanhToan}: ${paymentMethodLabel(row.paymentMethod)}',
          ),
          Text('${StockLabels.thamChieuDonHang}: ${row.linkedOrderRef ?? StockLabels.khongCo}'),
          Text(
            '${StockLabels.thamChieuThanhToan}: ${row.linkedPaymentRef ?? StockLabels.khongCo}',
          ),
        ],
      ),
    );
  }
}