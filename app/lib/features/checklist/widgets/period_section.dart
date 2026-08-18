import 'package:flutter/material.dart';

import 'history_entry_tile.dart';

/// A labelled section grouping checklist entries for one period of the day
/// (e.g. opening "Mở cửa" or closing "Đóng cửa").
///
/// Renders a small header row (icon + label) followed by one
/// [HistoryEntryTile] per entry.
class PeriodSection extends StatelessWidget {
  const PeriodSection({
    super.key,
    required this.label,
    required this.icon,
    required this.entries,
  });

  final String label;
  final IconData icon;
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...entries.map((entry) => HistoryEntryTile(entry: entry)),
      ],
    );
  }
}