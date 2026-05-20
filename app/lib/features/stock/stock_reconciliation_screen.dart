import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../data/models/category.dart';
import '../../providers/categories_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/utils/category_grouping.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/collapsible_category_sections.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/reconciliation_product_card.dart';
import 'widgets/reconciliation_submit_review_dialog.dart';
import 'stock_screen.dart';

class StockReconciliationScreen extends ConsumerStatefulWidget {
  const StockReconciliationScreen({super.key});

  @override
  ConsumerState<StockReconciliationScreen> createState() =>
      _StockReconciliationScreenState();
}

class _StockReconciliationScreenState
    extends ConsumerState<StockReconciliationScreen> {
  final CategorySectionExpansionController _categoryExpansionController =
      CategorySectionExpansionController();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(reconciliationProvider.notifier).loadDraft(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    final staffName = ref.watch(loggedByProvider).trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.doiSoatTonKhoHomNay),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: state.isSubmitting ? null : notifier.loadDraft,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: VN.lichSuDoiSoatTonKho,
            onPressed: state.isSubmitting
                ? null
                : () => context.push('/stock/reconciliation/history'),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: state.isLoading && state.draft == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, state, staffName),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: state.isSubmitting
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final canSubmit = ref
                      .read(reconciliationProvider.notifier)
                      .prepareSubmitReview();
                  final previewState = ref.read(reconciliationProvider);
                  final ok = await _confirmBeforeSubmit(
                    context,
                    previewState,
                    staffName,
                    canSubmit,
                  );
                  if (!ok) {
                    return;
                  }
                  if (!mounted) {
                    return;
                  }
                  final success = await ref
                      .read(reconciliationProvider.notifier)
                      .submit();
                  if (!mounted) {
                    return;
                  }
                  final nextState = ref.read(reconciliationProvider);
                  if (success) {
                    ref.invalidate(productsProvider);
                    ref.invalidate(stockOverviewProvider);
                    ref.invalidate(reconciliationHistoryListProvider);
                  }
                  final message = success
                      ? (nextState.submitSuccessMessage ?? VN.doiSoatThanhCong)
                      : (nextState.errorMessage ?? VN.doiSoatThatBai);
                  final background = success
                      ? Colors.green[700]
                      : Colors.red[700];
                  final isWasteOverInventory =
                      nextState.errorMessage != null &&
                      nextState.errorMessage!.contains(
                        'Số hao hụt vượt quá số thiếu',
                      );
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: background,
                        action: isWasteOverInventory
                            ? SnackBarAction(
                                label: VN.nhapHangSheet,
                                onPressed: () => context.push('/stock'),
                              )
                            : success &&
                                  nextState.lastSubmittedSessionId != null
                            ? SnackBarAction(
                                label: VN.xemLichSu,
                                onPressed: () => context.push(
                                  '/stock/reconciliation/history/${nextState.lastSubmittedSessionId}',
                                ),
                              )
                            : null,
                      ),
                    );
                },
          icon: state.isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(state.isSubmitting ? VN.dangGuiDoiSoat : VN.guiDoiSoat),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ReconciliationState state,
    String staffName,
  ) {
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final draft = state.draft;
    if (draft == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              state.errorMessage ?? VN.khongTheTaiDuLieuDoiSoat,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(VN.huongDanTaiLaiDoiSoat, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(reconciliationProvider.notifier).loadDraft(),
              icon: const Icon(Icons.refresh),
              label: const Text(VN.taiLai),
            ),
          ],
        ),
      );
    }

    final filteredProducts = draft.products
        .where((product) => product.expectedQty > 0)
        .toList(growable: false);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.orange.withValues(alpha: 0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${VN.ngayDoiSoat}: ${draft.date}'),
              const SizedBox(height: 4),
              Text(
                '${VN.nhanVien}: ${staffName.isEmpty ? VN.chuaChonNhanVien : staffName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text(VN.khongCoSanPhamTrungBay),
                        const SizedBox(height: 8),
                        const Text(
                          VN.huongDanKhongCoSanPhamTrungBay,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(reconciliationProvider.notifier)
                              .loadDraft(),
                          icon: const Icon(Icons.refresh),
                          label: const Text(VN.taiLai),
                        ),
                      ],
                    ),
                  ),
                )
              : CollapsibleCategorySections<ReconciliationDraftProduct>(
                  sections: groupItemsByCategory<ReconciliationDraftProduct>(
                    items: filteredProducts,
                    categories: categories,
                    categoryKeyOf: (product) => product.category,
                    itemLabelOf: (product) => product.name,
                  ),
                  expansionController: _categoryExpansionController,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  itemBuilder: (context, product) {
                    return ReconciliationProductCard(product: product);
                  },
                ),
        ),
      ],
    );
  }

  Future<bool> _confirmBeforeSubmit(
    BuildContext context,
    ReconciliationState state,
    String staffName,
    bool canSubmit,
  ) async {
    return showSubmitReviewDialog(
      context: context,
      state: state,
      staffName: staffName,
      canSubmit: canSubmit,
    );
  }
}
