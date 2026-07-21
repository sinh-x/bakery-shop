import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../shared/labels/shared.dart';
import 'reconciliation_history_sale_rows.dart';

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
                _SummaryChip(label: VN.tonDuKien, value: line.expectedQty),
                _SummaryChip(label: VN.tonDaDem, value: line.countedQty),
                _SummaryChip(label: VN.soLuongBan, value: line.saleQty),
                _SummaryChip(label: VN.soLuongHaoHut, value: line.wasteQty),
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
    final chipLabels = line.sourceChipLabels.isNotEmpty
        ? line.sourceChipLabels.join(', ')
        : line.chipLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.normalizedPrice != null
              ? '${VN.tuyChonGia}: ${line.normalizedPrice}'
              : '${VN.tuyChon}: $chipLabels',
        ),
        Text('${VN.tuyChon}: $chipLabels'),
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

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}