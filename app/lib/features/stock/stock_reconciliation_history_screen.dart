import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class StockReconciliationHistoryScreen extends ConsumerWidget {
  const StockReconciliationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(reconciliationHistoryListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.lichSuDoiSoatTonKho),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: () => ref.invalidate(reconciliationHistoryListProvider),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(VN.khongTaiDuocLichSuDoiSoat),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(reconciliationHistoryListProvider),
                icon: const Icon(Icons.refresh),
                label: const Text(VN.taiLai),
              ),
            ],
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const Center(child: Text(VN.chuaCoLichSuDoiSoat));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(reconciliationHistoryListProvider);
              await ref.read(reconciliationHistoryListProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final item = sessions[index];
                return ListTile(
                  title: Text('${VN.ngayDoiSoat}: ${item.reconciliationDate}'),
                  subtitle: Text(
                    '${VN.nhanVien}: ${item.staffName}\n${VN.soDong}: ${item.lineCount}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/stock/reconciliation/history/${item.id}');
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class StockReconciliationHistoryDetailScreen extends ConsumerWidget {
  const StockReconciliationHistoryDetailScreen({
    super.key,
    required this.sessionId,
  });

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      reconciliationHistoryDetailProvider(sessionId),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.chiTietDoiSoat),
        actions: const [AppBarOverflowMenu()],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.khongTaiDuocChiTietDoiSoat),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(
                  reconciliationHistoryDetailProvider(sessionId),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text(VN.taiLai),
              ),
            ],
          ),
        ),
        data: (detail) => _DetailView(detail: detail),
      ),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.detail});

  final ReconciliationHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('${VN.ngayDoiSoat}: ${detail.reconciliationDate}'),
        Text('${VN.nhanVien}: ${detail.staffName}'),
        Text(
          '${VN.phuongThucThanhToan}: ${paymentMethodLabel(detail.paymentMethod)}',
        ),
        Text(
          '${VN.lyDoHaoHut}: ${detail.wasteReason.isEmpty ? VN.khongCo : detail.wasteReason}',
        ),
        Text('${VN.thamChieuDonHang}: ${detail.linkedOrderRef ?? VN.khongCo}'),
        Text(
          '${VN.thamChieuThanhToan}: ${detail.linkedPaymentRef ?? VN.khongCo}',
        ),
        const SizedBox(height: 12),
        const Divider(),
        for (final line in detail.lines)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    line.normalizedPrice != null
                        ? '${VN.tuyChonGia}: ${line.normalizedPrice}'
                        : '${VN.tuyChon}: ${line.chipLabel}',
                  ),
                  Text(
                    '${VN.tuyChon}: ${line.sourceChipLabels.isNotEmpty ? line.sourceChipLabels.join(', ') : line.chipLabel}',
                  ),
                  const SizedBox(height: 6),
                  Text('${VN.tonDuKien}: ${line.expectedQty}'),
                  Text('${VN.tonDaDem}: ${line.countedQty}'),
                  Text('${VN.soLuongBan}: ${line.saleQty}'),
                  if (line.saleRows.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (var i = 0; i < line.saleRows.length; i++)
                      _SaleRowView(row: line.saleRows[i], index: i),
                  ],
                  Text('${VN.soLuongHaoHut}: ${line.wasteQty}'),
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
              ),
            ),
          ),
      ],
    );
  }
}

class _SaleRowView extends StatelessWidget {
  const _SaleRowView({required this.row, required this.index});

  final ReconciliationHistorySaleRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title = row.isLegacy
        ? '${index + 1}. Dòng bán cũ'
        : '${index + 1}. Dòng bán';
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
          Text('${VN.soLuongBan}: ${row.quantity}'),
          Text(
            '${VN.donGia}: ${row.unitPrice != null ? formatVND(row.unitPrice!) : VN.khongCo}',
          ),
          Text(
            '${VN.phuongThucThanhToan}: ${paymentMethodLabel(row.paymentMethod)}',
          ),
          Text('${VN.thamChieuDonHang}: ${row.linkedOrderRef ?? VN.khongCo}'),
          Text(
            '${VN.thamChieuThanhToan}: ${row.linkedPaymentRef ?? VN.khongCo}',
          ),
        ],
      ),
    );
  }
}
