import 'package:go_router/go_router.dart';

import '../../../data/api/receipt_service.dart';
import '../../../features/orders/cake_detail_screen.dart';
import '../../../features/orders/filtered_orders_screen.dart';
import '../../../features/orders/order_create_screen.dart';
import '../../../features/orders/order_detail_screen.dart';
import '../../../features/orders/order_edit_screen.dart';
import '../../../features/orders/order_history_screen.dart';
import '../../../features/orders/receipt_preview_screen.dart';
import '../../../features/events/event_form_screen.dart';

/// Order feature route definitions (DG-308 Phase 4.2 / FR-FL-4).
///
/// All routes use the root navigator key so they render full-screen outside
/// the shell scaffold.
List<RouteBase> ordersRoutes() => [
      GoRoute(
        path: '/orders/new',
        builder: (context, state) => const OrderCreateScreen(),
      ),
      GoRoute(
        path: '/orders/critical',
        builder: (context, state) =>
            const FilteredOrdersScreen(filter: 'critical'),
      ),
      GoRoute(
        path: '/orders/incomplete',
        builder: (context, state) =>
            const FilteredOrdersScreen(filter: 'incomplete'),
      ),
      GoRoute(
        path: '/orders/history',
        builder: (context, state) => const OrderHistoryScreen(),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) {
          final orderRef = state.pathParameters['id']!;
          return OrderDetailScreen(orderRef: orderRef);
        },
      ),
      GoRoute(
        path: '/orders/:id/incident/new',
        builder: (context, state) {
          final orderRef = state.pathParameters['id']!;
          final orderId = state.extra as int?;
          return EventFormScreen(orderRef: orderRef, orderId: orderId);
        },
      ),
      GoRoute(
        path: '/orders/:id/edit',
        builder: (context, state) {
          final orderRef = state.pathParameters['id']!;
          return OrderEditScreen(orderRef: orderRef);
        },
      ),
      GoRoute(
        path: '/orders/:id/items/:itemId',
        builder: (context, state) {
          final orderRef = state.pathParameters['id']!;
          final workItemId = state.pathParameters['itemId']!;
          return CakeDetailScreen(orderRef: orderRef, workItemId: workItemId);
        },
      ),
      GoRoute(
        path: '/orders/:id/receipt',
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
    ];