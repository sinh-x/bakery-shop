import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/checklist_provider.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/day_card.dart';

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
      ref
          .read(checklistHistoryProvider.notifier)
          .fetchRange(_fromDate, _toDate);
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
      ref
          .read(checklistHistoryProvider.notifier)
          .fetchRange(_fromDate, _toDate);
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
                    label: Text(_fmtDisplay(_fromDate)),
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
                          .fetchRange(_fromDate, _toDate),
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