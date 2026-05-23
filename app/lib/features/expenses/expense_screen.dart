import 'package:flutter/material.dart';

import '../../data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/shared/labels/events.dart';

class ExpenseScreen extends StatelessWidget {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.expenseTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            VN.expenseFormSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _ExpenseFormShell(),
          const SizedBox(height: 20),
          Text(
            VN.expenseHistorySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _ExpenseHistoryShell(),
        ],
      ),
    );
  }
}

class _ExpenseFormShell extends StatelessWidget {
  const _ExpenseFormShell();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            _FieldStub(label: VN.expenseAmountLabel),
            _FieldStub(label: VN.expenseCategoryLabel),
            _FieldStub(label: VN.expensePaymentMethodLabel),
            _FieldStub(label: VN.expenseVendorLabel),
            _FieldStub(label: VN.expenseNoteLabel),
            _FieldStub(label: VN.expenseStaffNameLabel),
          ],
        ),
      ),
    );
  }
}

class _ExpenseHistoryShell extends StatelessWidget {
  const _ExpenseHistoryShell();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'type=$expenseType, limit<=$expenseMaxHistoryLimit',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Bộ lọc dữ liệu đã sẵn sàng: ngày, danh mục, phương thức, nhân viên, tìm kiếm.',
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldStub extends StatelessWidget {
  const _FieldStub({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        enabled: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
