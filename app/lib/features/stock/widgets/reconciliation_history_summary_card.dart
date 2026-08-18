import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show paymentMethodLabel;
import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'package:bakery_app/shared/labels/stock.dart';
/// Summary card shown at the top of the reconciliation history detail view.
///
/// Renders session metadata (date, staff, payment method, waste reason) and
/// totals computed from [ReconciliationHistoryDetail.lines]: total expected,
/// counted, sale, waste, variance, product count, and line count.
class ReconciliationHistorySummaryCard extends StatelessWidget {
  const ReconciliationHistorySummaryCard({required this.detail, super.key});

  final ReconciliationHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    var totalExpected = 0;
    var totalCounted = 0;
    var totalSale = 0;
    var totalWaste = 0;
    for (final line in detail.lines) {
      totalExpected += line.expectedQty;
      totalCounted += line.countedQty;
      totalSale += line.saleQty;
      totalWaste += line.wasteQty;
    }
    final variance = totalExpected - totalCounted - totalSale - totalWaste;
    final productCount = detail.lines.map((line) => line.productId).toSet().length;
    final lineCount = detail.lines.length;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${StockLabels.ngayDoiSoat}: ${detail.reconciliationDate}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('${StockLabels.nhanVien}: ${detail.staffName}'),
            Text(
              '${StockLabels.phuongThucThanhToan}: ${paymentMethodLabel(detail.paymentMethod)}',
            ),
            Text(
              '${StockLabels.lyDoHaoHut}: ${detail.wasteReason.isEmpty ? StockLabels.khongCo : detail.wasteReason}',
            ),
            _RefRow(
              label: StockLabels.thamChieuDonHang,
              value: detail.linkedOrderRef,
            ),
            _RefRow(
              label: StockLabels.thamChieuThanhToan,
              value: detail.linkedPaymentRef,
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ReconciliationSummaryChip(
                  label: StockLabels.tongTonDuKien,
                  value: totalExpected,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongTonDaDem,
                  value: totalCounted,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongSoLuongBan,
                  value: totalSale,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongSoLuongHaoHut,
                  value: totalWaste,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongChenhLech,
                  value: variance,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongSoLuongSanPham,
                  value: productCount,
                ),
                ReconciliationSummaryChip(
                  label: StockLabels.tongSoDong,
                  value: lineCount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RefRow extends StatelessWidget {
  const _RefRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Text('$label: ${value ?? StockLabels.khongCo}');
  }
}

class ReconciliationSummaryChip extends StatelessWidget {
  const ReconciliationSummaryChip({required this.label, required this.value, super.key});

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