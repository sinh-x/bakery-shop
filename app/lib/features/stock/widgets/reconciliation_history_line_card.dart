import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../shared/labels/shared.dart';
import 'reconciliation_history_sale_rows.dart';
import 'reconciliation_history_summary_card.dart';

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
                  label: VN.tonDuKien,
                  value: line.expectedQty,
                ),
                ReconciliationSummaryChip(
                  label: VN.tonDaDem,
                  value: line.countedQty,
                ),
                ReconciliationSummaryChip(
                  label: VN.soLuongBan,
                  value: line.saleQty,
                ),
                ReconciliationSummaryChip(
                  label: VN.soLuongHaoHut,
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
              ? '${VN.tuyChonGia}: ${line.normalizedPrice}'
              : '${VN.tuyChon}: ${line.chipLabel}',
        ),
        Text('${VN.tuyChon}: $sourceChipLabels'),
        if (line.wasteQty > 0)
          Text(
            '${VN.lyDoHaoHut}: ${(line.wasteReason?.trim().isNotEmpty == true) ? line.wasteReason! : VN.khongCo}',
          ),
        Text(
          '${VN.donGiaNhapTay}: ${line.manualUnitPrice != null ? formatVND(line.manualUnitPrice!) : VN.khongCo}',
        ),
        Text(
          '${VN.thamChieuDongDonHang}: ${line.linkedOrderItemId?.toString() ?? VN.khongCo}',
        ),
        Text(
          '${VN.thamChieuXuatBan}: ${line.linkedStockMovementSaleId?.toString() ?? VN.khongCo}',
        ),
        Text(
          '${VN.thamChieuXuatHaoHut}: ${line.linkedStockMovementWasteId?.toString() ?? VN.khongCo}',
        ),
      ],
    );
  }
}