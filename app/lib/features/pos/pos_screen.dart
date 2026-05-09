// ignore_for_file: prefer_const_constructors  // DG-138#todo: replace with per-method suppressions after const audit
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/products_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import 'widgets/pos_cart_bar.dart';
import 'widgets/pos_product_grid.dart';

/// Main POS (Point of Sale) screen — 6th bottom tab.
/// Product-first flow with 3-tap quick sale for walk-in customers.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen>
    with WidgetsBindingObserver {
  int? _selectedCategoryIndex;
  String _searchQuery = '';
  Timer? _stockPollingTimer;
  bool _wasNavigatedAway = false;
  GoRouter? _goRouter;
  DateTime _lastStockRefreshAt = DateTime.now();

  /// Filtered products based on selected category and search query.
  List<Product> _filteredProducts(List<Product> products) {
    var result = products.where((p) => p.active == 1).toList();

    // Default: trung_bay products only (when no search)
    if (_searchQuery.isEmpty) {
      result = result
          .where((p) => p.attributes['trung_bay']?.toString() == 'true')
          .toList();
    } else {
      // Search: all products matching query
      final q = _searchQuery.toLowerCase();
      result = result.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    // Category filter
    if (_selectedCategoryIndex != null) {
      final categories = ref
          .read(categoriesProvider)
          .maybeWhen(data: (cats) => cats, orElse: () => <Category>[]);
      if (_selectedCategoryIndex! < categories.length) {
        final cat = categories[_selectedCategoryIndex!];
        result = result.where((p) => p.category == cat.slug).toList();
      }
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stockPollingTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshStock(),
    );
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
    _stockPollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStock();
    }
  }

  void _refreshStock() {
    ref.invalidate(productsProvider);
    if (mounted) {
      setState(() => _lastStockRefreshAt = DateTime.now());
    }
  }

  String _refreshLabel() {
    final ts = _lastStockRefreshAt;
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return VN.stockUpdatedAt('$hh:$mm');
  }

  void _onRouteChange() {
    if (!mounted) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == '/pos' && _wasNavigatedAway) {
      _wasNavigatedAway = false;
      _refreshStock();
    } else if (path != '/pos') {
      _wasNavigatedAway = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.banHang),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: _refreshStock,
          ),
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
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Kho hàng',
            onPressed: () => context.push('/stock'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: VN.searchProducts,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _refreshLabel(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Category tabs
          categoriesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(VN.categoryLoadError),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(categoriesProvider),
                    child: const Text(VN.taiLai),
                  ),
                ],
              ),
            ),
            data: (categories) {
              if (categories.isEmpty) return const SizedBox.shrink();
              final activeCats = categories
                  .where((c) => c.active == 1)
                  .toList();

              return SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: activeCats.length + 1, // +1 for "Tất cả"
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('Tất cả'),
                          selected: _selectedCategoryIndex == null,
                          onSelected: (_) =>
                              setState(() => _selectedCategoryIndex = null),
                        ),
                      );
                    }
                    final cat = activeCats[index - 1];
                    final emoji = cat.icon.isNotEmpty
                        ? cat.icon
                        : _categoryEmoji(cat.slug);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('$emoji ${cat.name}'),
                        selected: _selectedCategoryIndex == index - 1,
                        onSelected: (_) =>
                            setState(() => _selectedCategoryIndex = index - 1),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 8),

          // Product grid
          Expanded(
            child: Stack(
              children: [
                productsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(VN.apiError),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _refreshStock,
                          child: const Text(VN.taiLai),
                        ),
                      ],
                    ),
                  ),
                  data: (products) {
                    final filtered = _filteredProducts(products);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          VN.khongCoSanPham,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      );
                    }
                    return PosProductGrid(products: filtered);
                  },
                ),
                // Floating cart bar at bottom
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PosCartBar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoryEmoji(String slug) {
    return categoryEmojiMap[slug] ?? '📦';
  }
}
