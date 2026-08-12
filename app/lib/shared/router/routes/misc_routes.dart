import 'package:go_router/go_router.dart';

import '../../../features/accounting/accounting_screen.dart';
import '../../../features/audit_log/audit_log_screen.dart';
import '../../../features/categories/category_management_screen.dart';
import '../../../features/checklist/checklist_config_screen.dart';
import '../../../features/checklist/checklist_history_screen.dart';
import '../../../features/customers/customer_detail_screen.dart';
import '../../../features/customers/customer_list_screen.dart';
import '../../../features/customers/duplicate_finder_screen.dart';
import '../../../features/knowledge/knowledge_detail_screen.dart';
import '../../../features/knowledge/knowledge_form_screen.dart';
import '../../../features/knowledge/widgets/knowledge_edit_loader.dart';
import '../../../features/pos/pos_checkout_screen.dart';
import '../../../features/pos/pos_receipt_screen.dart';
import '../../../features/settings/address_library_screen.dart';
import '../../../features/settings/pre_login_settings_screen.dart';
import '../../../features/settings/settings_screen.dart';
import '../../../features/stock/stock_reconciliation_screen.dart';
import '../../../features/stock/stock_reconciliation_history_screen.dart';
import '../../../features/stock/stock_screen.dart';

/// All remaining full-screen routes not covered by the per-feature modules
/// (DG-308 Phase 4.2 / FR-FL-4).
List<RouteBase> miscRoutes() => [
      // Audit log — admin-only (Phase 8 filterable screen; route guard was
      // set up in Phase 7).
      GoRoute(
        path: '/audit-log',
        builder: (context, state) => const AuditLogScreen(),
      ),
      // Checklist config — full-screen (outside shell)
      GoRoute(
        path: '/checklist/config',
        builder: (context, state) => const ChecklistConfigScreen(),
      ),
      // Checklist history — full-screen (outside shell)
      GoRoute(
        path: '/checklist/history',
        builder: (context, state) => const ChecklistHistoryScreen(),
      ),
      // Category management — full-screen (outside shell)
      GoRoute(
        path: '/categories/manage',
        builder: (context, state) => const CategoryManagementScreen(),
      ),
      // Customer management — full-screen (outside shell)
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerListScreen(),
      ),
      // Duplicate finder — admin-only (DG-252 Phase 7 — FR7/AC4). Registered
      // BEFORE `/customers/:id` so the static `/duplicates` path is not
      // shadowed by the int path parameter. Staff users are redirected by the
      // router guard.
      GoRoute(
        path: '/customers/duplicates',
        builder: (context, state) => const DuplicateFinderScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return CustomerDetailScreen(customerId: id);
        },
      ),
      // Settings — full-screen (outside shell)
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Address library management — full-screen (DG-385 Phase 5 /
      // FR6/FR8/AC6). Reached from Settings → "Thư viện địa chỉ".
      GoRoute(
        path: '/settings/addresses',
        builder: (context, state) => const AddressLibraryScreen(),
      ),
      // Pre-login technical settings (DG-367 Phase 1 / FR4 / AC5) —
      // unauthenticated-accessible route for fixing the server URL before
      // login. Exempted in auth_guard.dart `unauthenticatedRoutes`.
      GoRoute(
        path: '/settings/connection',
        builder: (context, state) => const PreLoginSettingsScreen(),
      ),
      // POS checkout — full-screen (outside shell). The optional `fast`
      // query parameter triggers the Giao ngay fast-path (DG-370 Phase 1):
      // jumps directly to Stage 5 with walk-in defaults.
      GoRoute(
        path: '/pos/checkout',
        builder: (context, state) => PosCheckoutScreen(
          fastPath: state.uri.queryParameters['fast'] == 'true',
        ),
      ),
      // POS receipt — full-screen (outside shell)
      GoRoute(
        path: '/pos/receipt/:ref',
        builder: (context, state) {
          final orderRef = state.pathParameters['ref']!;
          return PosReceiptScreen(orderRef: orderRef);
        },
      ),
      // Stock management — full-screen (outside shell)
      GoRoute(
        path: '/stock',
        builder: (context, state) => const StockScreen(),
      ),
      GoRoute(
        path: '/stock/reconciliation',
        builder: (context, state) => const StockReconciliationScreen(),
      ),
      GoRoute(
        path: '/stock/reconciliation/history',
        builder: (context, state) => const StockReconciliationHistoryScreen(),
      ),
      GoRoute(
        path: '/stock/reconciliation/history/:id',
        builder: (context, state) {
          final sessionId = int.parse(state.pathParameters['id']!);
          return StockReconciliationHistoryDetailScreen(sessionId: sessionId);
        },
      ),
      // Accounting — full-screen (outside shell)
      GoRoute(
        path: '/accounting',
        builder: (context, state) => const AccountingScreen(),
      ),
      // Knowledge — full-screen (outside shell)
      GoRoute(
        path: '/knowledge/new',
        builder: (context, state) => const KnowledgeFormScreen(),
      ),
      GoRoute(
        path: '/knowledge/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return KnowledgeDetailScreen(entryId: id);
        },
      ),
      GoRoute(
        path: '/knowledge/:id/edit',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return KnowledgeEditLoader(entryId: id);
        },
      ),
    ];