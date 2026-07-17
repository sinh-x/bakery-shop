import 'package:flutter/material.dart';

import '../../../data/api/customer_service.dart';
import '../../../shared/labels/customers.dart';

/// One duplicate candidate group row in the finder screen (FR7/AC4).
///
/// Renders the group kind label (phone/name), the shared key, and each
/// member customer with name + phone + order count. The admin selects two
/// members by tapping (first tap = keep, second tap = merge-from) which then
/// triggers [onMerge]. The selection model works for any group size ≥2, so
/// groups of three or more members have a merge path (DG-252 review M3).
/// The merge target/choice is made by this tile from the admin's selection.
class DuplicateGroupTile extends StatefulWidget {
  const DuplicateGroupTile({
    super.key,
    required this.group,
    required this.onMerge,
    required this.merging,
  });

  final DuplicateGroup group;

  /// Called with `(keep, mergeFrom)` when the admin selects two members and
  /// confirms via the merge button. The screen is responsible for showing
  /// the confirmation dialog.
  final void Function(DuplicateCustomerEntry keep, DuplicateCustomerEntry mergeFrom)
      onMerge;

  /// Whether a merge is currently in flight for this group (disables actions).
  final bool merging;

  @override
  State<DuplicateGroupTile> createState() => _DuplicateGroupTileState();
}

class _DuplicateGroupTileState extends State<DuplicateGroupTile> {
  /// Ordered selection: first entry = keep, second entry = merge-from.
  /// Tapping a selected member deselects it (and any later selection).
  final List<int> _selectedIds = [];

  @override
  void didUpdateWidget(covariant DuplicateGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the group's membership changed (e.g. after a refresh), drop stale
    // selection ids that no longer exist in the group.
    final validIds = widget.group.customers.map((c) => c.id).toSet();
    _selectedIds.removeWhere((id) => !validIds.contains(id));
  }

  void _onMemberTap(DuplicateCustomerEntry entry) {
    if (widget.merging) return;
    setState(() {
      if (_selectedIds.contains(entry.id)) {
        _selectedIds.remove(entry.id);
        return;
      }
      if (_selectedIds.length >= 2) {
        // Replace the merge-from selection with the new pick.
        _selectedIds.removeLast();
      }
      _selectedIds.add(entry.id);
    });
  }

  String get _kindLabel => widget.group.kind == 'phone'
      ? CustomersLabels.duplicateFinderGroupPhoneLabel
      : CustomersLabels.duplicateFinderGroupNameLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canMerge = _selectedIds.length == 2 && !widget.merging;
    final keepId = _selectedIds.isNotEmpty ? _selectedIds.first : null;
    final mergeFromId = _selectedIds.length >= 2 ? _selectedIds.last : null;
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
                isKeep: c.id == keepId,
                isMergeFrom: c.id == mergeFromId,
                disabled: widget.merging,
                onTap: () => _onMemberTap(c),
              ),
            const SizedBox(height: 4),
            if (canMerge)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final keep = widget.group.customers.firstWhere(
                      (c) => c.id == keepId,
                    );
                    final mergeFrom = widget.group.customers.firstWhere(
                      (c) => c.id == mergeFromId,
                    );
                    widget.onMerge(keep, mergeFrom);
                    // Clear selection after dispatching; the merge dialog will
                    // run, and the screen refresh will rebuild this tile.
                    setState(_selectedIds.clear);
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
                    _selectedIds.length,
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
    required this.isKeep,
    required this.isMergeFrom,
    required this.disabled,
    required this.onTap,
  });

  final DuplicateCustomerEntry entry;
  final bool isKeep;
  final bool isMergeFrom;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = isKeep || isMergeFrom;
    final bgColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
        : theme.colorScheme.surfaceContainerHighest;
    final role = isKeep
        ? CustomersLabels.duplicateFinderMergeIntoLabel
        : isMergeFrom
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