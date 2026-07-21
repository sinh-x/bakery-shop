import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../shared/labels/shared.dart';

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
              '${VN.ngayDoiSoat}: ${detail.reconciliationDate}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('${VN.nhanVien}: ${detail.staffName}'),
            Text(
              '${VN.phuongThucThanhToan}: ${paymentMethodLabel(detail.paymentMethod)}',
            ),
            Text(
              '${VN.lyDoHaoHut}: ${detail.wasteReason.isEmpty ? VN.khongCo : detail.wasteReason}',
            ),
            _RefRow(
              label: VN.thamChieuDonHang,
              value: detail.linkedOrderRef,
            ),
            _RefRow(
              label: VN.thamChieuThanhToan,
              value: detail.linkedPaymentRef,
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SummaryPill(label: VN.tongTonDuKien, value: totalExpected),
                _SummaryPill(label: VN.tongTonDaDem, value: totalCounted),
                _SummaryPill(label: VN.tongSoLuongBan, value: totalSale),
                _SummaryPill(label: VN.tongSoLuongHaoHut, value: totalWaste),
                _SummaryPill(label: VN.tongChenhLech, value: variance),
                _SummaryPill(label: VN.tongSoLuongSanPham, value: productCount),
                _SummaryPill(label: VN.tongSoDong, value: lineCount),
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
    return Text('$label: ${value ?? VN.khongCo}');
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

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