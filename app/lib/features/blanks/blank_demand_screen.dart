import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blank_demand_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

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
        error: (e, _) => _DemandErrorView(
          onRetry: () => ref.read(blankDemandProvider.notifier).refresh(),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const _DemandEmptyView();
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(blankDemandProvider.notifier).refresh(),
            child: _DemandGroupedList(rows: rows),
          );
        },
      ),
    );
  }
}

class _DemandGroupedList extends StatelessWidget {
  const _DemandGroupedList({required this.rows});

  final List<BlankDemand> rows;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<BlankDemand>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.category, () => []).add(r);
    }
    final categories = groups.keys.toList()..sort();
    return ListView(
      children: [
        for (final category in categories) ...[
          _DemandCategoryHeader(category: category),
          for (final r in groups[category]!) _DemandRow(row: r),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _DemandCategoryHeader extends StatelessWidget {
  const _DemandCategoryHeader({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        category.isEmpty ? BlanksLabels.categoryFilterAll : category,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
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
            value: _format(row.demand),
            unit: row.unit,
          ),
          _DemandChip(
            label: BlanksLabels.demandStock,
            value: _format(row.stock),
            unit: row.unit,
          ),
          _DemandChip(
            label: BlanksLabels.demandShortfall,
            value: _format(row.shortage),
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

class _DemandEmptyView extends StatelessWidget {
  const _DemandEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.query_stats_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            BlanksLabels.emptyData,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _DemandErrorView extends StatelessWidget {
  const _DemandErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(VN.apiError, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}

String _format(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}