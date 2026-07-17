import 'package:flutter/material.dart';

import '../../../data/api/customer_service.dart';
import '../../../shared/labels/customers.dart';

/// One duplicate candidate group row in the finder screen (FR7/AC4).
///
/// Renders the group kind label (phone/name), the shared key, and each
/// member customer with name + phone + order count. The trailing "Gộp"
/// button triggers [onMerge] passing the chosen keep/merge-from pair. The
/// merge target/choice is made by the screen, not this tile.
class DuplicateGroupTile extends StatelessWidget {
  const DuplicateGroupTile({
    super.key,
    required this.group,
    required this.onMerge,
    required this.merging,
  });

  final DuplicateGroup group;

  /// Called with `(keep, mergeFrom)` when the admin taps a merge action.
  /// The screen is responsible for showing the confirmation dialog.
  final void Function(DuplicateCustomerEntry keep, DuplicateCustomerEntry mergeFrom)
      onMerge;

  /// Whether a merge is currently in flight for this group (disables actions).
  final bool merging;

  String get _kindLabel => group.kind == 'phone'
      ? CustomersLabels.duplicateFinderGroupPhoneLabel
      : CustomersLabels.duplicateFinderGroupNameLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  group.kind == 'phone'
                      ? Icons.phone_outlined
                      : Icons.person_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(_kindLabel, style: theme.textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.key,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final c in group.customers) _MemberRow(entry: c),
            const SizedBox(height: 4),
            if (group.customers.length == 2)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: merging
                      ? null
                      : () => onMerge(group.customers.first, group.customers.last),
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: const Text(CustomersLabels.duplicateFinderMergeButton),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${group.customers.length} khách — chọn 2 để gộp',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry});

  final DuplicateCustomerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            radius: 16,
            child: Text(entry.name.isEmpty ? '?' : entry.name[0]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: theme.textTheme.bodyLarge),
                if (entry.phone.isNotEmpty)
                  Text(entry.phone, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
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