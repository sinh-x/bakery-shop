import 'package:flutter/material.dart';

import '../../../data/models/journal_entry.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Card displaying a single journal entry with an expandable line-item table.
///
/// Extracted from journal_tab.dart (DG-189 Phase 1, finding M-2).
class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({super.key, required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDebit = entry.lines.fold<double>(
      0,
      (sum, l) => sum + l.debit,
    );
    final isLocked = entry.lockedAt != null && entry.lockedAt!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text(
          entry.description.isEmpty ? entry.sourceType : entry.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Row(
          children: [
            if (entry.createdAt != null) ...[
              Text(
                _formatTimestamp(entry.createdAt!),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.sourceType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
            ],
          ],
        ),
        trailing: Text(
          formatVND(totalDebit),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        VN.accountingFilterAccount,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        VN.accountingDebit,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        VN.accountingCredit,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                ...entry.lines.map((line) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${line.accountCode ?? ''} ${line.accountName ?? ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line.debit > 0 ? formatVND(line.debit) : '—',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line.credit > 0 ? formatVND(line.credit) : '—',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}