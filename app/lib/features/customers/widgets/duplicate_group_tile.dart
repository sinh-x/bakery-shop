import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../shared/labels/customers.dart';
import '../providers/duplicate_group_tile_notifier.dart';

/// One duplicate candidate group row in the finder screen (FR7/AC4).
///
/// Renders the group kind label (phone/name), the shared key, and each
/// member customer with name + phone + order count. The admin selects members
/// by tapping: the **first tap** designates the primary (keep) record, and
/// **subsequent taps** add sources (merge-from). Tapping a selected member
/// deselects it. When 2+ members are selected (1 primary + ≥1 source) the
/// merge button appears.
///
/// The selection model works for any group size ≥2, so groups of three or
/// more members have a merge path via batch merge (DG-369 Phase 3 — FR5/AC3).
/// For exactly two selected members the single-pair merge flow (with swap
/// affordance) is used; for 3+ the batch merge flow is used.
class DuplicateGroupTile extends ConsumerStatefulWidget {
  const DuplicateGroupTile({
    super.key,
    required this.group,
    required this.onMerge,
    required this.onBatchMerge,
    required this.merging,
  });

  final DuplicateGroup group;

  /// Called with `(keep, mergeFrom)` when the admin selects exactly two
  /// members and confirms via the merge button. The screen is responsible
  /// for showing the confirmation dialog.
  final void Function(DuplicateCustomerEntry keep, DuplicateCustomerEntry mergeFrom)
      onMerge;

  /// Called with `(primary, sources)` when the admin selects 3+ members
  /// (1 primary + ≥2 sources) and confirms via the merge button (DG-369
  /// Phase 3 — FR5/AC3). The screen is responsible for showing the batch
  /// confirmation dialog.
  final void Function(
    DuplicateCustomerEntry primary,
    List<DuplicateCustomerEntry> sources,
  ) onBatchMerge;

  /// Whether a merge is currently in flight for this group (disables actions).
  final bool merging;

  @override
  ConsumerState<DuplicateGroupTile> createState() =>
      _DuplicateGroupTileState();
}

class _DuplicateGroupTileState extends ConsumerState<DuplicateGroupTile> {
  late final NotifierProvider<DuplicateGroupTileNotifier,
      DuplicateGroupTileState> _provider =
      duplicateGroupTileProvider(widget.group.key);

  @override
  void didUpdateWidget(covariant DuplicateGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the group's membership changed (e.g. after a refresh), drop stale
    // selection ids that no longer exist in the group.
    final validIds = widget.group.customers.map((c) => c.id).toSet();
    ref.read(_provider.notifier).pruneInvalidIds(validIds);
  }

  void _onMemberTap(DuplicateCustomerEntry entry) {
    if (widget.merging) return;
    ref.read(_provider.notifier).toggleMember(entry.id);
  }

  String get _kindLabel => widget.group.kind == 'phone'
      ? CustomersLabels.duplicateFinderGroupPhoneLabel
      : CustomersLabels.duplicateFinderGroupNameLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = ref.watch(_provider);
    final selectedIds = selection.selectedIds;
    final selectedCount = selectedIds.length;
    final canMerge = selectedCount >= 2 && !widget.merging;
    final primaryId = selectedIds.isNotEmpty ? selectedIds.first : null;
    final sourceIds = selectedIds.length >= 2
        ? selectedIds.skip(1).toSet()
        : const <int>{};
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
                  widget.group.kind == 'phone'
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
                    widget.group.key,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final c in widget.group.customers)
              _MemberRow(
                entry: c,
                isPrimary: c.id == primaryId,
                isSource: sourceIds.contains(c.id),
                disabled: widget.merging,
                onTap: () => _onMemberTap(c),
              ),
            const SizedBox(height: 4),
            if (canMerge)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final selected = selectedIds
                        .map((id) => widget.group.customers
                            .firstWhere((c) => c.id == id))
                        .toList();
                    if (selected.length == 2) {
                      widget.onMerge(selected.first, selected.last);
                    } else {
                      widget.onBatchMerge(selected.first, selected.skip(1).toList());
                    }
                    // Clear selection after dispatching; the merge dialog
                    // will run, and the screen refresh will rebuild this
                    // tile.
                    ref.read(_provider.notifier).clearSelection();
                  },
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: const Text(CustomersLabels.duplicateFinderMergeButton),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  CustomersLabels.duplicateFinderPickTwoHint(
                    widget.group.customers.length,
                    selectedIds.length,
                  ),
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
  const _MemberRow({
    required this.entry,
    required this.isPrimary,
    required this.isSource,
    required this.disabled,
    required this.onTap,
  });

  final DuplicateCustomerEntry entry;
  final bool isPrimary;
  final bool isSource;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isPrimary
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : isSource
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHighest;
    final role = isPrimary
        ? CustomersLabels.duplicateFinderMergeIntoLabel
        : isSource
            ? CustomersLabels.duplicateFinderMergeFromLabel
            : null;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
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
            if (role != null) ...[
              Text(
                role,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              '${entry.orderCount} ${CustomersLabels.duplicateFinderOrderCountSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}