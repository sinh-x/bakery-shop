// ignore_for_file: prefer_const_constructors  // DG-138#todo: replace with per-method suppressions after const audit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/catalog_photo.dart';
import '../../data/models/event.dart';
import '../../data/api/receipt_service.dart';
import '../../data/providers/knowledge_provider.dart';
import '../../features/categories/category_management_screen.dart';
import '../../features/checklist/checklist_config_screen.dart';
import '../../features/checklist/checklist_history_screen.dart';
import '../../features/checklist/checklist_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/events/event_detail_screen.dart';
import '../../features/events/event_form_screen.dart';
import '../../features/events/event_list_screen.dart';
import '../../features/orders/cake_detail_screen.dart';
import '../../features/orders/order_create_screen.dart';
import '../../features/orders/order_detail_screen.dart';
import '../../features/orders/order_edit_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/orders/receipt_preview_screen.dart';
import '../../features/knowledge/knowledge_detail_screen.dart';
import '../../features/knowledge/knowledge_form_screen.dart';
import '../../features/knowledge/knowledge_list_screen.dart';
import '../../features/knowledge_base/knowledge_base_screen.dart';
import '../../features/pos/pos_checkout_screen.dart';
import '../../features/pos/pos_receipt_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/products/product_catalog_screen.dart';
import '../../features/products/catalog_browse_screen.dart';
import '../../features/products/widgets/catalog_photo_viewer.dart';
import '../../providers/catalog_provider.dart';
import '../../features/stock/stock_screen.dart';
import '../../features/stock/stock_reconciliation_screen.dart';
import '../../features/stock/stock_reconciliation_history_screen.dart';
import '../../features/products/product_form_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../providers/products_provider.dart';
import '../widgets/vietnamese_labels.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/orders',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => _ShellScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/orders',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: OrderListScreen()),
        ),
        GoRoute(
          path: '/products',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProductCatalogScreen()),
        ),
        GoRoute(
          path: '/knowledge-base',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: KnowledgeBaseScreen()),
        ),
        GoRoute(
          path: '/events',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: EventListScreen()),
        ),
        GoRoute(
          path: '/checklist',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ChecklistScreen()),
        ),
        GoRoute(
          path: '/knowledge',
          pageBuilder: (context, state) => NoTransitionPage(
            child: KnowledgeListScreen(
              initialType: state.uri.queryParameters['type'],
            ),
          ),
        ),
        GoRoute(
          path: '/pos',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: PosScreen()),
        ),
      ],
    ),
    // Checklist config — full-screen (outside shell)
    GoRoute(
      path: '/checklist/config',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ChecklistConfigScreen(),
    ),
    // Checklist history — full-screen (outside shell)
    GoRoute(
      path: '/checklist/history',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ChecklistHistoryScreen(),
    ),
    // Order create — full-screen (outside shell)
    GoRoute(
      path: '/orders/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrderCreateScreen(),
    ),
    // Order detail — full-screen (outside shell)
    GoRoute(
      path: '/orders/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        return OrderDetailScreen(orderRef: orderRef);
      },
    ),
    // Order edit — full-screen (outside shell)
    GoRoute(
      path: '/orders/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        return OrderEditScreen(orderRef: orderRef);
      },
    ),
    // Cake detail — full-screen (outside shell)
    GoRoute(
      path: '/orders/:id/items/:itemId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        final workItemId = state.pathParameters['itemId']!;
        return CakeDetailScreen(orderRef: orderRef, workItemId: workItemId);
      },
    ),
    // Receipt preview — full-screen (outside shell)
    GoRoute(
      path: '/orders/:id/receipt',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        final typeValue = state.uri.queryParameters['type'] ?? 'order';
        final itemIdStr = state.uri.queryParameters['item_id'];
        final itemId = itemIdStr != null ? int.tryParse(itemIdStr) : null;
        final receiptType = ReceiptType.values.firstWhere(
          (t) => t.value == typeValue,
          orElse: () => ReceiptType.workTicket,
        );
        return ReceiptPreviewScreen(
          orderRef: orderRef,
          receiptType: receiptType,
          itemId: itemId,
        );
      },
    ),
    // Product create — full-screen (outside shell)
    GoRoute(
      path: '/products/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ProductFormScreen(
        initialCategory: state.uri.queryParameters['category'],
      ),
    ),
    // Catalog browse — full-screen (outside shell)
    GoRoute(
      path: '/products/browse',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CatalogBrowseScreen(),
    ),
    // Catalog photo viewer (from browse screen) — full-screen (outside shell)
    GoRoute(
      path: '/products/:id/catalog',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        final initialPhotoId = state.extra as int?;
        return _CatalogViewerLoader(
          productId: id,
          initialPhotoId: initialPhotoId,
        );
      },
    ),
    // Product edit — full-screen (outside shell)
    GoRoute(
      path: '/products/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return _ProductEditLoader(productId: id);
      },
    ),
    // Event create — full-screen (outside shell)
    GoRoute(
      path: '/events/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const EventFormScreen(),
    ),
    // Event detail — full-screen (outside shell)
    GoRoute(
      path: '/events/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final event = state.extra as BakeryEvent;
        return EventDetailScreen(event: event);
      },
    ),
    // Event edit — full-screen (outside shell)
    GoRoute(
      path: '/events/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final event = state.extra as BakeryEvent;
        return EventFormScreen(event: event);
      },
    ),
    // Category management — full-screen (outside shell)
    GoRoute(
      path: '/categories/manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CategoryManagementScreen(),
    ),
    // Settings — full-screen (outside shell)
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
    ),
    // POS checkout — full-screen (outside shell)
    GoRoute(
      path: '/pos/checkout',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosCheckoutScreen(),
    ),
    // POS receipt — full-screen (outside shell)
    GoRoute(
      path: '/pos/receipt/:ref',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['ref']!;
        return PosReceiptScreen(orderRef: orderRef);
      },
    ),
    // Stock management — full-screen (outside shell)
    GoRoute(
      path: '/stock',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StockScreen(),
    ),
    GoRoute(
      path: '/stock/reconciliation',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StockReconciliationScreen(),
    ),
    GoRoute(
      path: '/stock/reconciliation/history',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StockReconciliationHistoryScreen(),
    ),
    GoRoute(
      path: '/stock/reconciliation/history/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final sessionId = int.parse(state.pathParameters['id']!);
        return StockReconciliationHistoryDetailScreen(sessionId: sessionId);
      },
    ),
    // Knowledge — full-screen (outside shell)
    GoRoute(
      path: '/knowledge/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const KnowledgeFormScreen(),
    ),
    GoRoute(
      path: '/knowledge/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return KnowledgeDetailScreen(entryId: id);
      },
    ),
    GoRoute(
      path: '/knowledge/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return _KnowledgeEditLoader(entryId: id);
      },
    ),
  ],
);

/// Loads the product from the API before showing the edit form.
class _ProductEditLoader extends ConsumerWidget {
  const _ProductEditLoader({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    // Try to find the product in the already-loaded list.
    return productsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text(VN.editProduct)),
        body: Center(child: Text(VN.apiError)),
      ),
      data: (products) {
        final product = products.where((p) => p.id == productId).firstOrNull;
        if (product == null) {
          return Scaffold(
            appBar: AppBar(title: const Text(VN.editProduct)),
            body: const Center(child: Text(VN.noProducts)),
          );
        }
        return ProductFormScreen(product: product);
      },
    );
  }
}

/// Loads a product's catalog photos and opens the viewer at the requested photo.
class _CatalogViewerLoader extends ConsumerWidget {
  const _CatalogViewerLoader({
    required this.productId,
    required this.initialPhotoId,
  });

  final int productId;
  final int? initialPhotoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider(productId));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return catalogAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, stackTrace) {
        return Scaffold(
          appBar: AppBar(title: const Text(VN.catalogTitle)),
          body: Center(child: Text(VN.apiError)),
        );
      },
      data: (photos) {
        if (photos.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text(VN.catalogTitle)),
            body: const Center(child: Text(VN.noCatalogPhotos)),
          );
        }
        final initialIndex = initialPhotoId == null
            ? 0
            : _findIndex(photos, initialPhotoId!);
        return CatalogPhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
          productId: productId,
          baseUrl: baseUrl,
        );
      },
    );
  }

  int _findIndex(List<CatalogPhoto> photos, int photoId) {
    final idx = photos.indexWhere((p) => p.id == photoId);
    return idx < 0 ? 0 : idx;
  }
}

/// Loads a knowledge entry from the API before showing the edit form.
class _KnowledgeEditLoader extends ConsumerWidget {
  const _KnowledgeEditLoader({required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(knowledgeEntryDetailProvider(entryId));
    return entryAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, stackTrace) {
        return Scaffold(
          appBar: AppBar(title: const Text(VN.editKnowledge)),
          body: Center(child: Text(VN.apiError)),
        );
      },
      data: (entry) {
        if (entry == null) {
          return Scaffold(
            appBar: AppBar(title: const Text(VN.editKnowledge)),
            body: const Center(child: Text(VN.apiError)),
          );
        }
        return KnowledgeFormScreen(entry: entry);
      },
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  final Widget child;

  const _ShellScaffold({required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) {
      return 0;
    }
    if (location.startsWith('/orders')) {
      return 1;
    }
    if (location.startsWith('/products')) {
      return 2;
    }
    if (location.startsWith('/knowledge-base') ||
        location.startsWith('/events') ||
        location.startsWith('/checklist') ||
        location.startsWith('/knowledge')) {
      return 3;
    }
    if (location.startsWith('/pos')) {
      return 4;
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
      case 1:
        context.go('/orders');
      case 2:
        context.go('/products');
      case 3:
        context.go('/knowledge-base');
      case 4:
        context.go('/pos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: VN.tabDashboard,
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: VN.tabOrders,
          ),
          NavigationDestination(
            icon: Icon(Icons.cake_outlined),
            selectedIcon: Icon(Icons.cake),
            label: VN.tabProducts,
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: VN.tabKnowledgeBase,
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: VN.banHang,
          ),
        ],
      ),
    );
  }
}
