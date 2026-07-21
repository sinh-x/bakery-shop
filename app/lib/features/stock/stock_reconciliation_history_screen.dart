import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/models/category.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../providers/categories_provider.dart';
import '../../shared/utils/category_grouping.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/collapsible_category_sections.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/reconciliation_history_line_card.dart';
import 'widgets/reconciliation_history_summary_card.dart';

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

class _DetailView extends ConsumerWidget {
  const _DetailView({required this.detail});

  final ReconciliationHistoryDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final sections = groupItemsByCategory<ReconciliationHistoryLine>(
      items: detail.lines,
      categories: categories,
      categoryKeyOf: (line) => line.category ?? '',
      itemLabelOf: (line) => line.productName,
    ).map((section) => section.categoryName.isEmpty
        ? GroupedCategorySection<ReconciliationHistoryLine>(
            categoryKey: section.categoryKey,
            categoryName: VN.khongPhanLoai,
            items: section.items,
            categoryPosition: section.categoryPosition,
          )
        : section).toList();

    if (sections.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ReconciliationHistorySummaryCard(detail: detail),
          const SizedBox(height: 24),
          const Center(child: Text(VN.khongCoSanPham)),
        ],
      );
    }

    return Column(
      children: [
        ReconciliationHistorySummaryCard(detail: detail),
        const SizedBox(height: 12),
        Expanded(
          child: CollapsibleCategorySections<ReconciliationHistoryLine>(
            sections: sections,
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            itemBuilder: (context, line) =>
                ReconciliationHistoryLineCard(line: line),
          ),
        ),
      ],
    );
  }
}
