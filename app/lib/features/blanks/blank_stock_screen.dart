import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blank_stock_provider.dart';
import '../../shared/utils/format_double.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blanks_category_grouped_list.dart';
import 'widgets/blanks_states.dart';
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
        error: (e, _) => BlanksErrorView(
          onRetry: () => ref.read(blankStockProvider.notifier).refresh(),
        ),
        data: (summaries) {
          if (summaries.isEmpty) {
            return const BlanksEmptyView(
              icon: Icons.inventory_2_outlined,
              label: BlanksLabels.emptyBlanks,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(blankStockProvider.notifier).refresh(),
            child: BlanksCategoryGroupedList<BlankStockSummary>(
              items: summaries,
              categoryKeyOf: (s) => s.category,
              itemLabelOf: (s) => s.name,
              itemBuilder: (context, s) => _StockRow(summary: s),
            ),
          );
        },
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
        '${formatDouble(summary.stock)}'
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