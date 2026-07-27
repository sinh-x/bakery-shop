import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blank_stock_log_provider.dart';
import '../../shared/utils/format_double.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blanks_states.dart';

/// Stock audit log screen — chronological history per blank (FR5 / AC5).
///
/// Route: `/blanks/:blankId/audit-log`. Lists all production/usage entries
/// for a single blank, newest-first, with quantity change, type,
/// produced/expiry dates and the entry timestamp. Empty state renders when
/// no history.
class BlankAuditLogScreen extends ConsumerWidget {
  const BlankAuditLogScreen({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(blankStockLogProvider(blankId));
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: BlanksLabels.actionSave,
            onPressed: () =>
                ref.read(blankStockLogProvider(blankId).notifier).refresh(),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: logAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(
          onRetry: () =>
              ref.read(blankStockLogProvider(blankId).notifier).refresh(),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const BlanksEmptyView(
              icon: Icons.history,
              label: BlanksLabels.emptyHistory,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(blankStockLogProvider(blankId).notifier).refresh(),
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _AuditLogEntryRow(entry: entries[index]),
            ),
          );
        },
      ),
    );
  }
}

class _AuditLogEntryRow extends StatelessWidget {
  const _AuditLogEntryRow({required this.entry});

  final BlankStockLog entry;

  @override
  Widget build(BuildContext context) {
    final isProduction = entry.type == 'production';
    final changeColor = isProduction ? Colors.green : Colors.red;
    final sign = isProduction ? '+' : '';
    final typeLabel = isProduction
        ? BlanksLabels.stockTypeProduction
        : BlanksLabels.stockTypeUsage;
    return ListTile(
      leading: Icon(
        isProduction ? Icons.add_circle : Icons.remove_circle,
        color: changeColor,
      ),
      title: Text(
        '$sign${formatDouble(entry.quantityChange)} ($typeLabel)',
        style: TextStyle(color: changeColor, fontWeight: FontWeight.bold),
      ),
      subtitle: Wrap(
        spacing: 12,
        children: [
          if (entry.createdAt != null)
            _MetaChip(label: BlanksLabels.fieldEntryDate, value: entry.createdAt!),
          if (entry.producedDate != null && entry.producedDate!.isNotEmpty)
            _MetaChip(
                label: BlanksLabels.fieldProducedDateShort,
                value: entry.producedDate!),
          if (entry.expiryDate != null && entry.expiryDate!.isNotEmpty)
            _MetaChip(
                label: BlanksLabels.fieldExpiryDateShort,
                value: entry.expiryDate!),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
    );
  }
}