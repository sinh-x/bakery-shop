import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'reconciliation_history_sale_rows.dart';
import 'reconciliation_history_summary_card.dart';
import 'package:bakery_app/shared/labels/stock.dart';
/// Collapsible card for a single reconciliation history line.
///
/// Collapsed: shows product name + key quantity chips (expected, counted,
/// sale, waste). Expanded: shows full details (price option, chip labels,
/// waste reason, manual unit price, linked references) and a collapsible
/// sale-rows section.
class ReconciliationHistoryLineCard extends StatefulWidget {
  const ReconciliationHistoryLineCard({required this.line, super.key});

  final ReconciliationHistoryLine line;

  @override
  State<ReconciliationHistoryLineCard> createState() =>
      _ReconciliationHistoryLineCardState();
}

class _ReconciliationHistoryLineCardState
    extends State<ReconciliationHistoryLineCard> {
  bool _isExpanded = false;
  bool _saleRowsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.productName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ReconciliationSummaryChip(
                  label: StockLabels.tonDuKien,
                  value: line.expectedQty,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tonDaDem,
                  value: line.countedQty,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.soLuongBan,
                  value: line.saleQty,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.soLuongHaoHut,
                  value: line.wasteQty,
                ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 10),
              _ExpandedDetails(line: line),
              if (line.saleRows.isNotEmpty)
                ReconciliationHistorySaleRowsSection(
                  saleRows: line.saleRows,
                  expanded: _saleRowsExpanded,
                  onToggle: () => setState(
                    () => _saleRowsExpanded = !_saleRowsExpanded,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpandedDetails extends StatelessWidget {
  const _ExpandedDetails({required this.line});

  final ReconciliationHistoryLine line;

  @override
  Widget build(BuildContext context) {
    final sourceChipLabels = line.sourceChipLabels.isNotEmpty
        ? line.sourceChipLabels.join(', ')
        : line.chipLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.normalizedPrice != null
              ? '${StockLabels.tuyChonGia}: ${line.normalizedPrice}'
              : '${StockLabels.tuyChon}: ${line.chipLabel}',
        ),
        Text('${StockLabels.tuyChon}: $sourceChipLabels'),
        if (line.wasteQty > 0)
          Text(
            '${StockLabels.lyDoHaoHut}: ${(line.wasteReason?.trim().isNotEmpty == true) ? line.wasteReason! : StockLabels.khongCo}',
          ),
        Text(
          '${StockLabels.donGiaNhapTay}: ${line.manualUnitPrice != null ? formatVND(line.manualUnitPrice!) : StockLabels.khongCo}',
        ),
        Text(
          '${StockLabels.thamChieuDongDonHang}: ${line.linkedOrderItemId?.toString() ?? StockLabels.khongCo}',
        ),
        Text(
          '${StockLabels.thamChieuXuatBan}: ${line.linkedStockMovementSaleId?.toString() ?? StockLabels.khongCo}',
        ),
        Text(
          '${StockLabels.thamChieuXuatHaoHut}: ${line.linkedStockMovementWasteId?.toString() ?? StockLabels.khongCo}',
        ),
      ],
    );
  }
}