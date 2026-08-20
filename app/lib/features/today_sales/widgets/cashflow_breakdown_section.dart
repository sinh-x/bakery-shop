import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../data/models/cash_drawer_transaction.dart';
import '../../../data/providers/cash_drawer_provider.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../cash_drawer/widgets/cash_drawer_breakdown_card.dart';

/// Cashflow breakdown section for the Today Sales screen
/// (DG-374 Phase 3 / FR5, FR6 / AC7, AC8).
///
/// Reuses [CashDrawerBreakdownCard] to render the categorized inflow/outflow
/// breakdown (sale, refund, expense, cashIn, cashOut, open, close, busShipping)
/// when an active cash drawer exists, by watching
/// [cashDrawerStatusProvider] and [cashDrawerTransactionsProvider] for the
/// active drawer's first transaction page.
///
/// When no active cash drawer exists (FR6/AC8), renders a placeholder message
/// ([SharedLabels.todaySalesNoActiveDrawer]) instead of the breakdown card —
/// graceful degradation so the rest of the Today Sales screen stays useful.
///
/// Coding standards (NFR2): the section widget is ≤300 lines and delegates
/// the heavy rendering to the existing [CashDrawerBreakdownCard] under
/// `features/cash_drawer/widgets/`.
class CashflowBreakdownSection extends ConsumerWidget {
  const CashflowBreakdownSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(cashDrawerStatusProvider);
    final drawer = statusAsync.asData?.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesCashflowSection),
        const SizedBox(height: 8),
        if (drawer == null)
          const _NoActiveDrawerPlaceholder()
        else
          _ActiveDrawerBreakdown(drawer: drawer),
      ],
    );
  }
}

class _ActiveDrawerBreakdown extends ConsumerWidget {
  const _ActiveDrawerBreakdown({required this.drawer});

  final CashDrawer drawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawerId = int.tryParse(drawer.id);
    if (drawerId == null) {
      // Malformed id — treat as no data and render an empty breakdown so the
      // section does not crash. The breakdown card renders all-zero rows.
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CashDrawerBreakdownCard(),
        ),
      );
    }
    final transactionsAsync = ref.watch(
      cashDrawerTransactionsProvider(
        CashDrawerTransactionsFilter(drawerId: drawerId),
      ),
    );
    final transactions =
        transactionsAsync.asData?.value.items ?? const <CashDrawerTransaction>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CashDrawerBreakdownCard(transactions: transactions),
      ),
    );
  }
}

class _NoActiveDrawerPlaceholder extends StatelessWidget {
  const _NoActiveDrawerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  SharedLabels.todaySalesNoActiveDrawer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
