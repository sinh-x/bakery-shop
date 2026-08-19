import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_service.dart';
import '../providers/reconciliation_history_line_card_notifier.dart';
import 'reconciliation_history_sale_rows.dart';
import 'reconciliation_history_summary_card.dart';
import 'package:bakery_app/shared/labels/stock.dart';
/// Collapsible card for a single reconciliation history line.
///
/// Collapsed: shows product name + key quantity chips (expected, counted,
/// sale, waste). Expanded: shows full details (price option, chip labels,
/// waste reason, manual unit price, linked references) and a collapsible
/// sale-rows section.
class ReconciliationHistoryLineCard extends ConsumerStatefulWidget {
  const ReconciliationHistoryLineCard({required this.line, super.key});

  final ReconciliationHistoryLine line;

  @override
  ConsumerState<ReconciliationHistoryLineCard> createState() =>
      _ReconciliationHistoryLineCardState();
}

class _ReconciliationHistoryLineCardState
    extends ConsumerState<ReconciliationHistoryLineCard> {
  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final cardState =
        ref.watch(reconciliationHistoryLineCardProvider(line.id));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => ref
                  .read(reconciliationHistoryLineCardProvider(line.id)
                      .notifier)
                  .toggleExpanded(),
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
                      cardState.isExpanded
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
            if (cardState.isExpanded) ...[
              const SizedBox(height: 10),
              _ExpandedDetails(line: line),
              if (line.saleRows.isNotEmpty)
                ReconciliationHistorySaleRowsSection(
                  saleRows: line.saleRows,
                  expanded: cardState.saleRowsExpanded,
                  onToggle: () => ref
                      .read(reconciliationHistoryLineCardProvider(line.id)
                          .notifier)
                      .toggleSaleRowsExpanded(),
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