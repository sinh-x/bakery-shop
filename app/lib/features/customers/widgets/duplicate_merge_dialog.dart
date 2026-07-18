import 'package:flutter/material.dart';

import '../../../data/api/customer_service.dart';
import '../../../shared/labels/customers.dart';

/// Confirmation dialog shown before merging a duplicate customer (FR7/AC4).
///
/// Displays both records' names, phones, and order counts side-by-side so
/// the admin can confirm the destructive merge. The "keep" customer becomes
/// the merge target (path param `customer_id`); the "merge-from" customer
/// becomes the source (`sourceCustomerId`) and is hard-deleted by the
/// backend. The admin can swap the keep/merge-from direction before
/// confirming (DG-252 review M3 — direction choice for the merge UI).
/// Returns a [MergeChoice] when the admin confirms, `null` otherwise.
class DuplicateMergeDialog extends StatefulWidget {
  const DuplicateMergeDialog({
    super.key,
    required this.keep,
    required this.mergeFrom,
  });

  /// Customer to keep (merge target) — initial direction; the admin can swap.
  final DuplicateCustomerEntry keep;

  /// Customer to merge into [keep] and delete (merge source) — initial
  /// direction; the admin can swap via the swap affordance.
  final DuplicateCustomerEntry mergeFrom;

  @override
  State<DuplicateMergeDialog> createState() => _DuplicateMergeDialogState();
}

/// Result returned by [DuplicateMergeDialog] reflecting the admin's chosen
/// keep/merge-from direction after an optional swap.
typedef MergeChoice = ({DuplicateCustomerEntry keep, DuplicateCustomerEntry mergeFrom});

class _DuplicateMergeDialogState extends State<DuplicateMergeDialog> {
  late bool _swapped;

  @override
  void initState() {
    super.initState();
    _swapped = false;
  }

  DuplicateCustomerEntry get _keep => _swapped ? widget.mergeFrom : widget.keep;
  DuplicateCustomerEntry get _mergeFrom =>
      _swapped ? widget.keep : widget.mergeFrom;

  void _toggleSwap() {
    setState(() => _swapped = !_swapped);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(CustomersLabels.duplicateFinderMergeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(CustomersLabels.duplicateFinderMergeDialogBody),
            const SizedBox(height: 16),
            _CustomerSummary(
              label: CustomersLabels.duplicateFinderMergeIntoLabel,
              entry: _keep,
              highlight: true,
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: IconButton.outlined(
                  onPressed: _toggleSwap,
                  tooltip: CustomersLabels.duplicateFinderSwapDirection,
                  icon: const Icon(Icons.swap_vert, size: 20),
                ),
              ),
            ),
            _CustomerSummary(
              label: CustomersLabels.duplicateFinderMergeFromLabel,
              entry: _mergeFrom,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<MergeChoice?>(null),
          child: const Text(CustomersLabels.duplicateFinderMergeCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop<MergeChoice?>((
            keep: _keep,
            mergeFrom: _mergeFrom,
          )),
          child: const Text(CustomersLabels.duplicateFinderMergeConfirm),
        ),
      ],
    );
  }
}

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