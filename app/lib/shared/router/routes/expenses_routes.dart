import 'package:go_router/go_router.dart';

import '../../../data/models/event.dart';
import '../../../features/expenses/debt_list_screen.dart';
import '../../../features/expenses/debt_settlement_screen.dart';
import '../../../features/expenses/expense_screen.dart';
import '../../../features/expenses/expense_form_screen.dart';

/// Expense feature route definitions (DG-308 Phase 4.2 / FR-FL-4).
List<RouteBase> expensesRoutes() => [
      GoRoute(
        path: '/expenses',
        builder: (context, state) => ExpenseScreen(
          onOpenDebts: () => context.push('/expenses/debts'),
        ),
      ),
      GoRoute(
        path: '/expenses/new',
        builder: (context, state) => const ExpenseFormScreen(),
      ),
      GoRoute(
        path: '/expenses/:id/edit',
        builder: (context, state) {
          final event = state.extra as BakeryEvent;
          return ExpenseFormScreen(event: event);
        },
      ),
      // Outstanding debts list (DG-212 Phase 4 — FR5)
      GoRoute(
        path: '/expenses/debts',
        builder: (context, state) => const DebtListScreen(),
      ),
      // Debt settlement flow (DG-212 Phase 4 — FR4, AC3)
      GoRoute(
        path: '/expenses/:id/settle',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return DebtSettlementScreen(eventId: id);
        },
      ),
    ];