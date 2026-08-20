import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatting.dart';

/// A single checklist history entry rendered as a dense [ListTile].
///
/// Shows the template name with a leading check/cancel icon and, when
/// completed, the completing user plus a formatted timestamp. Uncompleted
/// entries render greyed out with a "Chưa hoàn thành" subtitle.
class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({super.key, required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final completed = entry['completed'] == true;
    final name = entry['template_name'] as String? ?? 'Mục checklist';
    final completedBy = entry['completed_by'] as String?;
    final completedAt = entry['completed_at'] as String?;

    return ListTile(
      dense: true,
      leading: Icon(
        completed ? Icons.check_circle : Icons.cancel_outlined,
        color: completed ? Colors.green : Colors.grey,
        size: 20,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: completed ? null : Colors.grey,
          decoration: completed ? null : null,
        ),
      ),
      subtitle: completed && completedBy != null && completedBy.isNotEmpty
          ? Text(
              '$completedBy${_fmtTime(completedAt)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
            )
          : Text(
              'Chưa hoàn thành',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
      tileColor: completed ? Colors.green.withValues(alpha: 0.04) : null,
    );
  }

  String _fmtTime(String? completedAt) {
    final dt = parseApiDateTime(completedAt);
    if (dt == null) return '';
    return ' • ${formatDisplayTime(dt)}';
  }
}