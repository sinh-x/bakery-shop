import 'package:flutter/material.dart';

import '../../../data/api/customer_service.dart';
import '../../../shared/labels/customers.dart';

/// Batch merge confirmation dialog (DG-369 Phase 3 — FR6/AC4).
///
/// Lists the primary (keep) record and all source (merge-from) records with
/// their names, phones, and order counts so the admin can confirm the
/// destructive batch merge. Cancel returns `null`; confirm returns the
/// primary plus the list of sources.
///
/// Returns a [BatchMergeChoice] when the admin confirms, `null` otherwise.
class DuplicateBatchMergeDialog extends StatelessWidget {
  const DuplicateBatchMergeDialog({
    super.key,
    required this.primary,
    required this.sources,
  });

  /// Customer to keep (merge target) — path param `customer_id`.
  final DuplicateCustomerEntry primary;

  /// Customers to merge into [primary] and delete (body `sourceCustomerIds`).
  final List<DuplicateCustomerEntry> sources;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(CustomersLabels.duplicateFinderBatchMergeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(CustomersLabels.duplicateFinderBatchMergeDialogBody),
            const SizedBox(height: 16),
            _CustomerSummary(
              label: CustomersLabels.duplicateFinderBatchMergePrimaryLabel,
              entry: primary,
              highlight: true,
            ),
            const SizedBox(height: 12),
            Text(
              CustomersLabels.duplicateFinderBatchMergeSourcesLabel,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CustomerSummary(
                  label: CustomersLabels.duplicateFinderMergeFromLabel,
                  entry: source,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop<BatchMergeChoice?>(null),
          child: const Text(CustomersLabels.duplicateFinderBatchMergeCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop<BatchMergeChoice?>((
            primary: primary,
            sources: sources,
          )),
          child: const Text(CustomersLabels.duplicateFinderBatchMergeConfirm),
        ),
      ],
    );
  }
}

/// Result returned by [DuplicateBatchMergeDialog] reflecting the admin's
/// confirmed batch merge choice: the primary (keep) record plus the list of
/// source (merge-from) records.
typedef BatchMergeChoice = ({
  DuplicateCustomerEntry primary,
  List<DuplicateCustomerEntry> sources,
});

class _CustomerSummary extends StatelessWidget {
  const _CustomerSummary({
    required this.label,
    required this.entry,
    this.highlight = false,
  });

  final String label;
  final DuplicateCustomerEntry entry;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: highlight ? theme.colorScheme.primary : null,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(entry.name, style: nameStyle),
          if (entry.phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(entry.phone, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          Text(
            '${entry.orderCount} ${CustomersLabels.duplicateFinderOrderCountSuffix}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}