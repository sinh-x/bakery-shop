import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/stock_service.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/utils/category_grouping.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/collapsible_category_sections.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/stock_action_sheet.dart';
import 'widgets/stock_item_card.dart';

/// Provider for stock overview list.
final stockOverviewProvider =
    AsyncNotifierProvider<StockOverviewNotifier, List<StockOverviewItem>>(
      StockOverviewNotifier.new,
    );

class StockOverviewNotifier extends AsyncNotifier<List<StockOverviewItem>> {
  @override
  Future<List<StockOverviewItem>> build() async {
    return _fetch();
  }

  Future<List<StockOverviewItem>> _fetch() async {
    final service = ref.read(stockServiceProvider);
    return service.getStockOverview();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Stock status colors based on quantity.
///
/// Negative stock (DG-200 Phase 5, FR-8, AC-10) uses a distinct darker red
/// shade (`Colors.red.shade900`) so cashiers can visually distinguish an
/// oversold position from a merely out-of-stock (zero) product.
Color stockStatusColor(int quantity) {
  if (quantity < 0) return Colors.red.shade900;
  if (quantity == 0) return Colors.red;
  if (quantity <= 3) return Colors.orange;
  return Colors.green;
}

/// Stock status label based on quantity.
///
/// Negative stock returns the VN label "Âm N" (where N is the absolute
/// quantity) per FR-8 / AC-10. Zero stock returns "Hết hàng".
String stockStatusLabel(int quantity) {
  if (quantity < 0) return VN.negativeStockLabel(quantity);
  if (quantity == 0) return VN.outOfStock;
  if (quantity <= 3) return 'Sắp hết';
  return 'Còn hàng';
}

/// Main stock management screen.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final CategorySectionExpansionController _categoryExpansionController =
      CategorySectionExpansionController();

  @override
  String screenRoutePath() => '/stock';

  @override
  void invalidateProviders() {
    ref.invalidate(stockOverviewProvider);
  }

  @override
  void initState() {
    super.initState();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    super.dispose();
  }

  void _onAppBarMenuSelected(String value) {
    switch (value) {
      case 'stock_reconciliation':
        context.push('/stock/reconciliation');
        return;
      case 'stock_reconciliation_history':
        context.push('/stock/reconciliation/history');
        return;
      default:
        assert(() {
          debugPrint('Unknown stock app bar menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockOverviewProvider);
    final categories = ref.watch(categoriesProvider).asData?.value ?? const [];
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.quanLyTonKho),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: () => ref.invalidate(stockOverviewProvider),
          ),
          AppBarOverflowMenu(
            onSelected: _onAppBarMenuSelected,
            items: const [
              PopupMenuItem<String>(
                value: 'stock_reconciliation',
                child: Text(VN.openStockReconciliation),
              ),
              PopupMenuItem<String>(
                value: 'stock_reconciliation_history',
                child: Text(VN.openStockReconciliationHistory),
              ),
            ],
          ),
        ],
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(VN.apiError, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(stockOverviewProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    VN.khongCoSanPhamTonKho,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          final groupedSections = groupItemsByCategory<StockOverviewItem>(
            items: items,
            categories: categories,
            categoryKeyOf: (item) => item.category,
            itemLabelOf: (item) => item.productName,
          );

          return RefreshIndicator(
            onRefresh: () => ref.read(stockOverviewProvider.notifier).refresh(),
            child: CollapsibleCategorySections<StockOverviewItem>(
              sections: groupedSections,
              expansionController: _categoryExpansionController,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, item) {
                final emoji = categoryEmojiMap[item.category] ?? '🍰';
                return StockItemCard(
                  item: item,
                  emoji: emoji,
                  baseUrl: baseUrl,
                  cacheBuster: photoRefreshTick.toString(),
                  onRestock: () =>
                      _showActionSheet(context, ref, item, ActionType.restock),
                  onWaste: () =>
                      _showActionSheet(context, ref, item, ActionType.waste),
                  onAdjust: () =>
                      _showActionSheet(context, ref, item, ActionType.adjust),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showActionSheet(
    BuildContext context,
    WidgetRef ref,
    StockOverviewItem item,
    ActionType type,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StockActionSheet(
        item: item,
        actionType: type,
        onDone: () {
          ref.read(stockOverviewProvider.notifier).refresh();
          Navigator.pop(context);
          showTopSnackBar(context, VN.capNhatThanhCong);
        },
      ),
    );
  }
}
