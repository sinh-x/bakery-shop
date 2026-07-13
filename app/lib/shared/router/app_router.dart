import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/order/incomplete_count_provider.dart';
import '../../providers/order/urgency_count_provider.dart';

import '../../data/api/api_client.dart';
import '../../data/models/catalog_photo.dart';
import '../../data/models/event.dart';
import '../../data/api/receipt_service.dart';
import '../../data/providers/knowledge_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/categories/category_management_screen.dart';
import '../../features/checklist/checklist_config_screen.dart';
import '../../features/checklist/checklist_history_screen.dart';
import '../../features/customers/customer_detail_screen.dart';
import '../../features/customers/customer_list_screen.dart';
import '../../features/checklist/checklist_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/expenses/expense_screen.dart';
import '../../features/expenses/expense_form_screen.dart';
import '../../features/expenses/debt_list_screen.dart';
import '../../features/expenses/debt_settlement_screen.dart';
import '../../features/events/event_detail_screen.dart';
import '../../features/events/event_form_screen.dart';
import '../../features/events/event_list_screen.dart';
import '../../features/orders/cake_detail_screen.dart';
import '../../features/orders/filtered_orders_screen.dart';
import '../../features/orders/order_create_screen.dart';
import '../../features/orders/order_detail_screen.dart';
import '../../features/orders/order_edit_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/orders/order_history_screen.dart';
import '../../features/accounting/accounting_screen.dart';
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
import '../widgets/admin_guard.dart';
import 'package:bakery_app/shared/labels/shared.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Auth-redirect guard (FR14/FR15, AC8/AC9).
///
/// - When the auth state is `unauthenticated`, any route other than `/login`
///   redirects to `/login`.
/// - When the auth state is `authenticated`, `/login` redirects to `/orders`
///   (the main shell).
/// - While the auth state is `unknown` (initial boot, before the notifier has
///   resolved the stored token) the guard does nothing — the splash/loading
///   state is owned by the `/login` route's initial frame.
///
/// Role-based gating (FR16/AC10/AC11): when authenticated, staff users are
/// blocked from the admin-only routes listed in [_adminOnlyRoutes]. They are
/// redirected to the dedicated [_adminAccessRoute] page so deep links do not
/// silently land on a blank screen. Admin users pass through unaffected.
String? _authRedirect(GoRouterState state, AuthStatus status, String? role) {
  final location = state.uri.path;
  final onLogin = location == '/login';
  switch (status) {
    case AuthStatus.authenticated:
      if (onLogin) return '/orders';
      if (role != 'admin' && _isAdminOnlyRoute(location)) {
        return _adminAccessRoute;
      }
      return null;
    case AuthStatus.unauthenticated:
      return onLogin ? null : '/login';
    case AuthStatus.unknown:
      return null;
  }
}

/// Admin-only routes (FR16). Staff users are redirected away from these.
///
/// NOTE: `/audit-log` is registered here as a placeholder route for Phase 8;
/// Phase 7 only ensures its nav entry and route guard are admin-gated. The
/// audit log *screen with filters* is built in Phase 8.
const Set<String> _adminOnlyRoutes = {
  '/checklist/config',
  '/categories/manage',
  '/stock/reconciliation',
  '/stock/reconciliation/history',
  '/audit-log',
};

/// Match admin-only routes that take path parameters (e.g.
/// `/stock/reconciliation/history/123`). Prefix match is used for those.
bool _isAdminOnlyRoute(String location) {
  if (_adminOnlyRoutes.contains(location)) return true;
  for (final route in _adminOnlyRoutes) {
    if (location.startsWith('$route/')) return true;
  }
  return false;
}

const String _adminAccessRoute = '/admin-access';

/// Router provider — listens to [authProvider] so that auth state changes
/// (login, logout, 401 handling) trigger the redirect guard without needing
/// a manual `router.refresh()`.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/orders',
    redirect: (context, state) =>
        _authRedirect(state, authState.status, authState.role),
    routes: [
      // Login — full-screen, outside the shell (FR14/AC8).
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      // Admin access denied — shown when staff hit an admin-only route (FR16).
      GoRoute(
        path: _adminAccessRoute,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AdminAccessScreen(),
      ),
      // Audit log — admin-only placeholder route (Phase 7 gating only; the
      // filterable screen is built in Phase 8).
      GoRoute(
        path: '/audit-log',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const _AuditLogPlaceholder(),
      ),
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
      path: '/orders/critical',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FilteredOrdersScreen(filter: 'critical'),
    ),
    GoRoute(
      path: '/orders/incomplete',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FilteredOrdersScreen(filter: 'incomplete'),
    ),
    GoRoute(
      path: '/orders/history',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrderHistoryScreen(),
    ),
    GoRoute(
      path: '/orders/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        return OrderDetailScreen(orderRef: orderRef);
      },
    ),
    // Order incident — full-screen (outside shell)
    GoRoute(
      path: '/orders/:id/incident/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final orderRef = state.pathParameters['id']!;
        final orderId = state.extra as int?;
        return EventFormScreen(orderRef: orderRef, orderId: orderId);
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
    // Expense screen shell — full-screen (outside shell)
    GoRoute(
      path: '/expenses',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ExpenseScreen(
        onOpenDebts: () => context.push('/expenses/debts'),
      ),
    ),
    GoRoute(
      path: '/expenses/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ExpenseFormScreen(),
    ),
    GoRoute(
      path: '/expenses/:id/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final event = state.extra as BakeryEvent;
        return ExpenseFormScreen(event: event);
      },
    ),
    // Outstanding debts list (DG-212 Phase 4 — FR5)
    GoRoute(
      path: '/expenses/debts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DebtListScreen(),
    ),
    // Debt settlement flow (DG-212 Phase 4 — FR4, AC3)
    GoRoute(
      path: '/expenses/:id/settle',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return DebtSettlementScreen(eventId: id);
      },
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
    // Customer management — full-screen (outside shell)
    GoRoute(
      path: '/customers',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CustomerListScreen(),
    ),
    GoRoute(
      path: '/customers/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return CustomerDetailScreen(customerId: id);
      },
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
    // Accounting — full-screen (outside shell)
    GoRoute(
      path: '/accounting',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountingScreen(),
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
});

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
        body: const Center(child: Text(VN.apiError)),
      ),
      data: (products) {
        final product = products.where((p) => p.id == productId).firstOrNull;
        if (product != null) {
          return ProductFormScreen(product: product);
        }

        final productAsync = ref.watch(productByIdProvider(productId));
        return productAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: const Text(VN.editProduct)),
            body: const Center(child: Text(VN.apiError)),
          ),
          data: (product) => ProductFormScreen(product: product),
        );
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
          body: const Center(child: Text(VN.apiError)),
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
          body: const Center(child: Text(VN.apiError)),
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

class _ShellScaffold extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final urgencyCount = ref.watch(urgencyCountProvider);
    final incompleteCount = ref.watch(incompleteCountProvider);
    final showUrgencyBadge = urgencyCount > 0;
    final showIncompleteBadge = incompleteCount > 0;

    Widget ordersIcon({required IconData icon}) {
      if (!showUrgencyBadge && !showIncompleteBadge) {
        return Icon(icon);
      }
      final children = <Widget>[
        Icon(icon),
      ];
      if (showUrgencyBadge) {
        children.add(
          Positioned(
            right: -2,
            top: -2,
            child: _BadgeCircle(color: Colors.red, count: urgencyCount),
          ),
        );
      }
      if (showIncompleteBadge) {
        children.add(
          Positioned(
            right: -2,
            top: showUrgencyBadge ? 14 : -2,
            child: _BadgeCircle(color: Colors.amber, count: incompleteCount),
          ),
        );
      }
      return Stack(clipBehavior: Clip.none, children: children);
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: VN.tabDashboard,
          ),
          NavigationDestination(
            icon: ordersIcon(icon: Icons.receipt_long_outlined),
            selectedIcon: ordersIcon(icon: Icons.receipt_long),
            label: VN.tabOrders,
          ),
          const NavigationDestination(
            icon: Icon(Icons.cake_outlined),
            selectedIcon: Icon(Icons.cake),
            label: VN.tabProducts,
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: VN.tabKnowledgeBase,
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: VN.banHang,
          ),
        ],
      ),
    );
  }
}

/// Small circular badge dot for nav tab indicators.
class _BadgeCircle extends StatelessWidget {
  const _BadgeCircle({
    required this.color,
    required this.count,
  });

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Placeholder for the `/audit-log` route (Phase 7). The full filterable
/// audit log screen is built in Phase 8 — this only ensures the route exists
/// and is admin-gated by the redirect guard in [_authRedirect].
class _AuditLogPlaceholder extends StatelessWidget {
  const _AuditLogPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.openAuditLog)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tính năng nhật ký thay đổi sẽ có ở giai đoạn tiếp theo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
