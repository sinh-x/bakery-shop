import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/blank.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

/// A single blank row in the blanks list.
///
/// Shows name, category chip, unit, and a notes preview. Tapping the row
/// navigates to the blank detail screen (`/blanks/:id`).
class BlankTile extends StatelessWidget {
  const BlankTile({super.key, required this.blank});

  final Blank blank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(blank.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (blank.category.isNotEmpty)
                _BlankChip(label: blank.category),
              if (blank.unit.isNotEmpty)
                _BlankChip(label: blank.unit, icon: Icons.scale_outlined),
            ],
          ),
          if (blank.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              blank.notes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/blanks/${blank.id}'),
    );
  }
}

class _BlankChip extends StatelessWidget {
  const _BlankChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable category filter chip bar.
///
/// Renders a leading "Tất cả danh mục" chip followed by one chip per unique
/// category. Calls [onSelected] with the chosen category (empty string for
/// "all"). The currently selected category is highlighted.
class BlankCategoryFilterBar extends StatelessWidget {
  const BlankCategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final all = <String>[
      BlanksLabels.categoryFilterAll,
      ...categories,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = all[index];
          final isSelected = index == 0
              ? selected.isEmpty
              : selected == label;
          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onSelected(index == 0 ? '' : label),
          );
        },
      ),
    );
  }
}