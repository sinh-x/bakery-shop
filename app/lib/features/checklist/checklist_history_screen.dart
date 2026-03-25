import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/checklist_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class ChecklistHistoryScreen extends ConsumerStatefulWidget {
  const ChecklistHistoryScreen({super.key});

  @override
  ConsumerState<ChecklistHistoryScreen> createState() =>
      _ChecklistHistoryScreenState();
}

class _ChecklistHistoryScreenState
    extends ConsumerState<ChecklistHistoryScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    _toDate = DateTime.now();
    _fromDate = _toDate.subtract(const Duration(days: 6));
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2024),
      lastDate: _toDate,
      helpText: 'Chọn ngày bắt đầu',
    );
    if (picked != null && picked != _fromDate) {
      setState(() => _fromDate = picked);
      ref.read(checklistHistoryProvider.notifier).fetchRange(_fromDate, _toDate);
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: _fromDate,
      lastDate: DateTime.now(),
      helpText: 'Chọn ngày kết thúc',
    );
    if (picked != null && picked != _toDate) {
      setState(() => _toDate = picked);
      ref.read(checklistHistoryProvider.notifier).fetchRange(_fromDate, _toDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(checklistHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử Checklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () => ref
                .read(checklistHistoryProvider.notifier)
                .fetchRange(_fromDate, _toDate),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Từ:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_fmtDisplay(_fromDate)),
                    onPressed: _pickFromDate,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Đến:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_fmtDisplay(_toDate)),
                    onPressed: _pickToDate,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // History list
          Expanded(
            child: historyAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(VN.apiError),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref
                          .read(checklistHistoryProvider.notifier)
                          .fetchRange(_fromDate, _toDate),
                      child: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (days) {
                if (days.isEmpty) {
                  return const Center(
                    child: Text(
                      'Không có dữ liệu lịch sử',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final dayData = days[index];
                    return _DayCard(dayData: dayData);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDisplay(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _DayCard extends StatefulWidget {
  const _DayCard({required this.dayData});

  final Map<String, dynamic> dayData;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.dayData['date'] as String? ?? '';
    final entriesRaw = widget.dayData['entries'] as List? ?? [];
    final entries = entriesRaw.cast<Map<String, dynamic>>();

    final completedCount = entries.where((e) => e['completed'] == true).length;
    final totalCount = entries.length;

    final openingEntries = entries
        .where((e) => e['template_period'] == 'opening')
        .toList()
      ..sort((a, b) =>
          (a['template_sort_order'] as int? ?? 0)
              .compareTo(b['template_sort_order'] as int? ?? 0));
    final closingEntries = entries
        .where((e) => e['template_period'] == 'closing')
        .toList()
      ..sort((a, b) =>
          (a['template_sort_order'] as int? ?? 0)
              .compareTo(b['template_sort_order'] as int? ?? 0));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          // Day header — tappable to expand/collapse
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                _PeriodSection(
                  label: 'Mở cửa',
                  icon: Icons.wb_sunny_outlined,
                  entries: openingEntries,
                ),
              ],
              if (closingEntries.isNotEmpty) ...[
                if (openingEntries.isNotEmpty) const Divider(height: 1),
                _PeriodSection(
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
    try {
      final dt = DateTime.parse(isoDate);
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
      return '$weekday, ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _PeriodSection extends StatelessWidget {
  const _PeriodSection({
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
              Icon(icon, size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        ...entries.map((entry) => _HistoryEntryTile(entry: entry)),
      ],
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final completed = entry['completed'] == true;
    final name =
        entry['template_name'] as String? ?? 'Mục checklist';
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                  ),
            )
          : Text(
              'Chưa hoàn thành',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
      tileColor: completed ? Colors.green.withValues(alpha: 0.04) : null,
    );
  }

  String _fmtTime(String? completedAt) {
    if (completedAt == null) return '';
    try {
      final dt = DateTime.parse(completedAt);
      return ' • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
