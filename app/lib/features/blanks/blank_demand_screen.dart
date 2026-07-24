import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blank_demand_provider.dart';
import '../../shared/utils/format_double.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blanks_category_grouped_list.dart';
import 'widgets/blanks_states.dart';

/// Demand planning screen — demand vs stock vs shortage per blank
/// (FR3 / AC4).
///
/// Route: `/blanks/demand`. Lists each blank with its demand, current stock
/// and computed shortage (positive = shortfall), grouped by category.
/// Rows with a positive shortage are highlighted in red/amber. Pull-to-refresh
/// reloads the overview. Loading, empty, and error states render inline.
class BlankDemandScreen extends ConsumerWidget {
  const BlankDemandScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandAsync = ref.watch(blankDemandProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenDemand),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: BlanksLabels.actionSave,
            onPressed: () => ref.read(blankDemandProvider.notifier).refresh(),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: demandAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(
          onRetry: () => ref.read(blankDemandProvider.notifier).refresh(),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const BlanksEmptyView(
              icon: Icons.query_stats_outlined,
              label: BlanksLabels.emptyData,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(blankDemandProvider.notifier).refresh(),
            child: BlanksCategoryGroupedList<BlankDemand>(
              items: rows,
              categoryKeyOf: (r) => r.category,
              itemLabelOf: (r) => r.name,
              itemBuilder: (context, r) => _DemandRow(row: r),
            ),
          );
        },
      ),
    );
  }
}

class _DemandRow extends StatelessWidget {
  const _DemandRow({required this.row});

  final BlankDemand row;

  @override
  Widget build(BuildContext context) {
    final hasShortage = row.shortage > 0;
    final shortageColor = hasShortage ? Colors.red : Colors.green;
    return ListTile(
      title: Text(
        row.name,
        style: hasShortage
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      subtitle: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DemandChip(
            label: BlanksLabels.demand,
            value: formatDouble(row.demand),
            unit: row.unit,
          ),
          _DemandChip(
            label: BlanksLabels.demandStock,
            value: formatDouble(row.stock),
            unit: row.unit,
          ),
          _DemandChip(
            label: BlanksLabels.demandShortfall,
            value: formatDouble(row.shortage),
            unit: row.unit,
            color: shortageColor,
            emphasize: hasShortage,
          ),
        ],
      ),
      trailing: hasShortage
          ? const Icon(Icons.warning_amber_rounded, color: Colors.red)
          : const Icon(Icons.check_circle_outline, color: Colors.green),
    );
  }
}

class _DemandChip extends StatelessWidget {
  const _DemandChip({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String unit;
  final Color? color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final text = unit.isEmpty ? '$label: $value' : '$label: $value $unit';
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: emphasize ? FontWeight.bold : null,
          ),
    );
  }
}