import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/blank.dart';
import '../../data/models/work_item.dart';
import '../../data/providers/blank_demand_provider.dart';
import '../../data/providers/blank_stock_provider.dart';
import '../../data/providers/blanks_provider.dart';
import '../../shared/utils/format_double.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blank_form.dart';
import 'widgets/blanks_states.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// View / edit / delete a single blank (FR1 / AC1).
///
/// Route: `/blanks/:id`. Displays all blank fields, with actions to edit
/// (opens [BlankForm] in edit mode), delete (with confirmation dialog), and
/// an audit log button. BOM mapping is keyed by price_chip (not blank), so
/// it is accessed from the product/price_chip flow rather than here.
///
/// DG-293 Phase 4 also surfaces stock summary (FR4), demand (FR5), and a
/// reverse lookup of linked products/work items (FR6 / AC3-AC4).
class BlankDetailScreen extends ConsumerWidget {
  const BlankDetailScreen({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blankAsync = ref.watch(blankByIdProvider(blankId));
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenDetail),
        actions: const [AppBarOverflowMenu()],
      ),
      body: blankAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(
          onRetry: () => ref.invalidate(blankByIdProvider(blankId)),
        ),
        data: (blank) => _BlankDetailBody(blankId: blank.id, blank: blank),
      ),
    );
  }
}

class _BlankDetailBody extends ConsumerWidget {
  const _BlankDetailBody({required this.blankId, required this.blank});

  final int blankId;
  final Blank blank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BlankFieldRow(label: BlanksLabels.fieldName, value: blank.name),
        _BlankFieldRow(label: BlanksLabels.fieldCategory, value: blank.category),
        _BlankFieldRow(label: BlanksLabels.fieldUnit, value: blank.unit),
        _BlankFieldRow(label: BlanksLabels.fieldNote, value: blank.notes),
        const SizedBox(height: 24),
        _StockSummarySection(blankId: blankId),
        const SizedBox(height: 16),
        _DemandSummarySection(blankId: blankId),
        const SizedBox(height: 24),
        _LinkedProductsSection(blankId: blankId),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => showBlankForm(context, blank: blank),
          icon: const Icon(Icons.edit),
          label: const Text(BlanksLabels.actionEdit),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/blanks/$blankId/audit-log'),
          icon: const Icon(Icons.history),
          label: const Text(BlanksLabels.screenHistory),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _confirmDelete(context, ref),
          icon: const Icon(Icons.delete_outline),
          label: const Text(BlanksLabels.actionDelete),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: const Text(BlanksLabels.messageDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(BlanksLabels.actionCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(BlanksLabels.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(blanksProvider.notifier).deleteBlank(blankId);
      if (context.mounted) {
        showTopSnackBar(context, BlanksLabels.messageDeleteSuccess);
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, BlanksLabels.messageDeleteBlocked);
      }
    }
  }
}

/// Stock summary card for a single blank (FR4 / AC4). Shows the current net
/// stock level from `blank_stock`. Renders nothing when the API has no row.
class _StockSummarySection extends ConsumerWidget {
  const _StockSummarySection({required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(blankStockByIdProvider(blankId));
    return _SummaryCard(
      title: BlanksLabels.sectionStock,
      icon: Icons.inventory_2_outlined,
      child: stockAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (s) => Text(
          s == null
              ? BlanksLabels.emptyData
              // ignore: use_build_context_synchronously
              : _formatStock(s.stock, s.unit),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  String _formatStock(double stock, String unit) {
    final unitLabel = unit.isEmpty ? '' : ' $unit';
    return '${formatDecimal(stock)}$unitLabel';
  }
}

/// Demand summary card for a single blank (FR5 / AC4). Shows demand, current
/// stock, and shortage from the demand calculation endpoint.
class _DemandSummarySection extends ConsumerWidget {
  const _DemandSummarySection({required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandAsync = ref.watch(blankDemandByIdProvider(blankId));
    return _SummaryCard(
      title: BlanksLabels.sectionDemand,
      icon: Icons.trending_up_outlined,
      child: demandAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (d) {
          if (d == null) return const Text(BlanksLabels.emptyData);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DemandRow(
                label: BlanksLabels.demand,
                value: formatDecimal(d.demand),
              ),
              _DemandRow(
                label: BlanksLabels.demandStock,
                value: formatDecimal(d.stock),
              ),
              _DemandRow(
                label: BlanksLabels.demandShortage,
                value: formatDecimal(d.shortage),
                emphasize: d.shortage > 0,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DemandRow extends StatelessWidget {
  const _DemandRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: style?.copyWith(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: emphasize
                  ? style?.copyWith(color: Colors.red, fontWeight: FontWeight.bold)
                  : style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reverse-lookup section: products linked via BOM and work items linked via
/// the `blank_id` FK (FR6 / AC3). Work item rows navigate to the order detail.
class _LinkedProductsSection extends ConsumerWidget {
  const _LinkedProductsSection({required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(blankProductsProvider(blankId));
    return _SummaryCard(
      title: BlanksLabels.sectionLinkedProducts,
      icon: Icons.link_outlined,
      child: productsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (p) {
          final hasBom = p.bomProducts.isNotEmpty;
          final hasItems = p.workItems.isNotEmpty;
          if (!hasBom && !hasItems) {
            return const Text(BlanksLabels.linkedEmpty);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBom) ...[
                Text(
                  BlanksLabels.linkedBomProducts,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                for (final b in p.bomProducts) _BomProductTile(product: b),
                if (hasItems) const SizedBox(height: 12),
              ],
              if (hasItems) ...[
                Text(
                  BlanksLabels.linkedWorkItems,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                for (final w in p.workItems) _WorkItemTile(item: w),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BomProductTile extends StatelessWidget {
  const _BomProductTile({required this.product});

  final BlankBomProduct product;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cake_outlined, size: 20),
      title: Text(
        product.productName.isEmpty ? '—' : product.productName,
      ),
      subtitle: Text(
        '${BlanksLabels.linkedBomQuantity}: ${formatDecimal(product.quantity)}',
      ),
      onTap: product.productId == null
          ? null
          : () => context.push('/products/${product.productId}/edit'),
    );
  }
}

class _WorkItemTile extends StatelessWidget {
  const _WorkItemTile({required this.item});

  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_outlined, size: 20),
      title: Text(item.productName.isEmpty ? '—' : item.productName),
      subtitle: Text(
        '#${item.orderId} • ${BlanksLabels.linkedWorkItemQuantity}: ${item.quantity}',
      ),
      onTap: () => context.push('/orders/${item.orderId}'),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _BlankFieldRow extends StatelessWidget {
  const _BlankFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}