import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatting.dart';
import 'period_section.dart';

/// Expandable day card for the checklist history list.
///
/// Renders a tappable header showing the formatted weekday/date and a
/// "completed/total" counter. When expanded it shows the day's entries grouped
/// by template period (opening "Mở cửa" / closing "Đóng cửa"). The expand
/// toggle is local UI state, which is an acceptable use of `setState` per
/// §4 animation/widget-toggle exception.
class DayCard extends StatefulWidget {
  const DayCard({super.key, required this.dayData});

  final Map<String, dynamic> dayData;

  @override
  State<DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<DayCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.dayData['date'] as String? ?? '';
    final entriesRaw = widget.dayData['entries'] as List? ?? [];
    final entries = entriesRaw.cast<Map<String, dynamic>>();

    final completedCount = entries.where((e) => e['completed'] == true).length;
    final totalCount = entries.length;

    final openingEntries =
        entries.where((e) => e['template_period'] == 'opening').toList()..sort(
          (a, b) => (a['template_sort_order'] as int? ?? 0).compareTo(
            b['template_sort_order'] as int? ?? 0,
          ),
        );
    final closingEntries =
        entries.where((e) => e['template_period'] == 'closing').toList()..sort(
          (a, b) => (a['template_sort_order'] as int? ?? 0).compareTo(
            b['template_sort_order'] as int? ?? 0,
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          // Day header — tappable to expand/collapse
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDateHeader(dateStr),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '$completedCount/$totalCount hoàn thành',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: completedCount == totalCount && totalCount > 0
                          ? Colors.green
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_expanded) ...[
            const Divider(height: 1),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Không có mục nào trong ngày này',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else ...[
              if (openingEntries.isNotEmpty) ...[
                PeriodSection(
                  label: 'Mở cửa',
                  icon: Icons.wb_sunny_outlined,
                  entries: openingEntries,
                ),
              ],
              if (closingEntries.isNotEmpty) ...[
                if (openingEntries.isNotEmpty) const Divider(height: 1),
                PeriodSection(
                  label: 'Đóng cửa',
                  icon: Icons.nights_stay_outlined,
                  entries: closingEntries,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  String _formatDateHeader(String isoDate) {
    final dt = parseApiDate(isoDate);
    if (dt == null) return isoDate;
    const weekdays = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ nhật',
    ];
    final weekday = weekdays[dt.weekday - 1];
    return '$weekday, ${formatDisplayDate(dt)}';
  }
}