import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blank_stock_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/stock_action_sheet.dart';

/// Stock tracking screen — current net stock per blank (FR4 / AC3).
///
/// Route: `/blanks/stock`. Lists each blank with its name, category, unit and
/// current net stock, grouped by category. Each row exposes production
/// (nhập kho) and usage (xuất kho) action buttons that open the
/// [BlankStockActionSheet]. Pull-to-refresh reloads the overview.
/// Loading, empty, and error states render inline.
class BlankStockScreen extends ConsumerWidget {
  const BlankStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(blankStockProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenStock),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: BlanksLabels.actionSave,
            onPressed: () => ref.read(blankStockProvider.notifier).refresh(),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _StockErrorView(
          onRetry: () => ref.read(blankStockProvider.notifier).refresh(),
        ),
        data: (summaries) {
          if (summaries.isEmpty) {
            return const _StockEmptyView();
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(blankStockProvider.notifier).refresh(),
            child: _StockGroupedList(summaries: summaries),
          );
        },
      ),
    );
  }
}

class _StockGroupedList extends StatelessWidget {
  const _StockGroupedList({required this.summaries});

  final List<BlankStockSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<BlankStockSummary>>{};
    for (final s in summaries) {
      groups.putIfAbsent(s.category, () => []).add(s);
    }
    final categories = groups.keys.toList()..sort();
    return ListView(
      children: [
        for (final category in categories) ...[
          _StockCategoryHeader(category: category),
          for (final s in groups[category]!) _StockRow(summary: s),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _StockCategoryHeader extends StatelessWidget {
  const _StockCategoryHeader({required this.category});

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

class _StockRow extends StatelessWidget {
  const _StockRow({required this.summary});

  final BlankStockSummary summary;

  @override
  Widget build(BuildContext context) {
    final stockColor = summary.stock <= 0
        ? Colors.red
        : summary.stock <= 3
            ? Colors.orange
            : Colors.green;
    return ListTile(
      title: Text(summary.name),
      subtitle: Text(
        '${BlanksLabels.demandStock}: '
        '${_formatStock(summary.stock)}'
        '${summary.unit.isNotEmpty ? ' ${summary.unit}' : ''}',
        style: TextStyle(color: stockColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.green),
            tooltip: BlanksLabels.actionStockIn,
            onPressed: () => showBlankStockActionSheet(
              context,
              summary,
              BlankStockAction.production,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            tooltip: BlanksLabels.actionStockOut,
            onPressed: () => showBlankStockActionSheet(
              context,
              summary,
              BlankStockAction.usage,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockEmptyView extends StatelessWidget {
  const _StockEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            BlanksLabels.emptyBlanks,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _StockErrorView extends StatelessWidget {
  const _StockErrorView({required this.onRetry});

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

String _formatStock(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}