import 'package:go_router/go_router.dart';

import '../../../features/blanks/blank_audit_log_screen.dart';
import '../../../features/blanks/blank_demand_screen.dart';
import '../../../features/blanks/blank_detail_screen.dart';
import '../../../features/blanks/blank_list_screen.dart';
import '../../../features/blanks/blank_stock_screen.dart';
import '../../../features/blanks/bom_mapping_screen.dart';

/// Blanks feature route definitions (DG-308 Phase 4.2 / FR-FL-4).
///
/// Static routes are registered BEFORE `/blanks/:blankId` so the int path
/// parameter does not shadow them (DG-291 Phase 4.10 — FR1-FR6/NFR4).
List<RouteBase> blanksRoutes() => [
      GoRoute(
        path: '/blanks',
        builder: (context, state) => const BlankListScreen(),
      ),
      GoRoute(
        path: '/blanks/stock',
        builder: (context, state) => const BlankStockScreen(),
      ),
      GoRoute(
        path: '/blanks/demand',
        builder: (context, state) => const BlankDemandScreen(),
      ),
      GoRoute(
        path: '/blanks/bom/:priceChipId',
        builder: (context, state) {
          final priceChipId = int.parse(state.pathParameters['priceChipId']!);
          return BomMappingScreen(priceChipId: priceChipId);
        },
      ),
      GoRoute(
        path: '/blanks/:blankId',
        builder: (context, state) {
          final blankId = int.parse(state.pathParameters['blankId']!);
          return BlankDetailScreen(blankId: blankId);
        },
      ),
      GoRoute(
        path: '/blanks/:blankId/audit-log',
        builder: (context, state) {
          final blankId = int.parse(state.pathParameters['blankId']!);
          return BlankAuditLogScreen(blankId: blankId);
        },
      ),
    ];