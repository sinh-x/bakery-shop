import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/stock_service.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/stock_action_sheet.dart';

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
    state = await AsyncValue.guard(() => _fetch());
  }
}

/// Stock status colors based on quantity.
Color stockStatusColor(int quantity) {
  if (quantity <= 0) return Colors.red;
  if (quantity <= 3) return Colors.orange;
  return Colors.green;
}

/// Stock status label based on quantity.
String stockStatusLabel(int quantity) {
  if (quantity <= 0) return 'Hết hàng';
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
    with WidgetsBindingObserver {
  bool _wasNavigatedAway = false;
  GoRouter? _goRouter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (_goRouter != router) {
      _goRouter?.routerDelegate.removeListener(_onRouteChange);
      _goRouter = router;
      _goRouter?.routerDelegate.addListener(_onRouteChange);
    }
  }

  @override
  void dispose() {
    _goRouter?.routerDelegate.removeListener(_onRouteChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(stockOverviewProvider);
    }
  }

  void _onRouteChange() {
    if (!mounted) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == '/stock' && _wasNavigatedAway) {
      _wasNavigatedAway = false;
      ref.invalidate(stockOverviewProvider);
    } else if (path != '/stock') {
      _wasNavigatedAway = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockOverviewProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.quanLyTonKho),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: VN.doiSoatTonKhoHomNay,
            onPressed: () => context.push('/stock/reconciliation'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: VN.lichSuDoiSoatTonKho,
            onPressed: () => context.push('/stock/reconciliation/history'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: () => ref.invalidate(stockOverviewProvider),
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

          return RefreshIndicator(
            onRefresh: () => ref.read(stockOverviewProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final emoji = categoryEmojiMap[item.category] ?? '🍰';
                return _StockItemCard(
                  item: item,
                  emoji: emoji,
                  baseUrl: baseUrl,
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

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.emoji,
    required this.baseUrl,
    required this.onRestock,
    required this.onWaste,
    required this.onAdjust,
  });

  final StockOverviewItem item;
  final String emoji;
  final String baseUrl;
  final VoidCallback onRestock;
  final VoidCallback onWaste;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final statusColor = stockStatusColor(item.quantity);
    final statusLabel = stockStatusLabel(item.quantity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '$baseUrl/api/products/${item.productId}/photo',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[100],
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 32)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Quantity
            Column(
              children: [
                Text(
                  '${item.quantity}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                Text(
                  VN.tonKho,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Action buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: VN.nhapHang,
                    onPressed: onRestock,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.remove, size: 18),
                    tooltip: VN.haoHut,
                    onPressed: onWaste,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: VN.dieuChinh,
                    onPressed: onAdjust,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
