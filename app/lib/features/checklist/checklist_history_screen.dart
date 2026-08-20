import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/checklist_provider.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'providers/checklist_history_filter_notifier.dart';
import 'widgets/day_card.dart';

class ChecklistHistoryScreen extends ConsumerStatefulWidget {
  const ChecklistHistoryScreen({super.key});

  @override
  ConsumerState<ChecklistHistoryScreen> createState() =>
      _ChecklistHistoryScreenState();
}

class _ChecklistHistoryScreenState
    extends ConsumerState<ChecklistHistoryScreen> {
  Future<void> _pickFromDate() async {
    final filter = ref.read(checklistHistoryFilterProvider);
    final fromDate = filter.fromDate;
    final toDate = filter.toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate,
      firstDate: DateTime(2024),
      lastDate: toDate,
      helpText: 'Chọn ngày bắt đầu',
    );
    if (picked != null && picked != fromDate) {
      ref.read(checklistHistoryFilterProvider.notifier).setFromDate(picked);
      ref
          .read(checklistHistoryProvider.notifier)
          .fetchRange(picked, toDate);
    }
  }

  Future<void> _pickToDate() async {
    final filter = ref.read(checklistHistoryFilterProvider);
    final fromDate = filter.fromDate;
    final toDate = filter.toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate,
      firstDate: fromDate,
      lastDate: DateTime.now(),
      helpText: 'Chọn ngày kết thúc',
    );
    if (picked != null && picked != toDate) {
      ref.read(checklistHistoryFilterProvider.notifier).setToDate(picked);
      ref
          .read(checklistHistoryProvider.notifier)
          .fetchRange(fromDate, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(checklistHistoryFilterProvider);
    final fromDate = filter.fromDate;
    final toDate = filter.toDate;
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
                .fetchRange(fromDate, toDate),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: Column(
        children: [
          // Date range selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Từ:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_fmtDisplay(fromDate)),
                    onPressed: _pickFromDate,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Đến:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_fmtDisplay(toDate)),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(SharedLabels.apiError),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref
                          .read(checklistHistoryProvider.notifier)
                          .fetchRange(fromDate, toDate),
                      child: const Text(SharedLabels.retry),
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
                    return DayCard(dayData: dayData);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDisplay(DateTime dt) => formatDisplayDate(dt);
}