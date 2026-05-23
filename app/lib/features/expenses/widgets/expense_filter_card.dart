import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';

enum ExpenseDateFilterMode { single, range }

class ExpenseFilterCard extends StatelessWidget {
  const ExpenseFilterCard({
    super.key,
    required this.searchCtrl,
    required this.since,
    required this.until,
    required this.dateFilterMode,
    required this.categories,
    required this.staffNames,
    required this.filterCategory,
    required this.filterStaffName,
    required this.onDateFilterModeChanged,
    required this.onPickDate,
    required this.onFilterCategoryChanged,
    required this.onFilterStaffChanged,
    required this.onClearFilters,
    required this.onApplyFilters,
    required this.formatDate,
  });

  final TextEditingController searchCtrl;
  final DateTime? since;
  final DateTime? until;
  final ExpenseDateFilterMode dateFilterMode;
  final List<String> categories;
  final List<String> staffNames;
  final String filterCategory;
  final String filterStaffName;
  final ValueChanged<ExpenseDateFilterMode> onDateFilterModeChanged;
  final VoidCallback onPickDate;
  final ValueChanged<String> onFilterCategoryChanged;
  final ValueChanged<String> onFilterStaffChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onApplyFilters;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = since == null || until == null
        ? VN.lichSuDonHangLocKhoangNgay
        : '${formatDate(since!)} - ${formatDate(until!)}';
    final singleLabel = since == null ? VN.expenseSinceLabel : formatDate(since!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                labelText: VN.expenseSearchLabel,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(VN.lichSuDonHangLocMotNgay),
                  selected: dateFilterMode == ExpenseDateFilterMode.single,
                  onSelected: (_) =>
                      onDateFilterModeChanged(ExpenseDateFilterMode.single),
                ),
                ChoiceChip(
                  label: const Text(VN.lichSuDonHangLocKhoangNgay),
                  selected: dateFilterMode == ExpenseDateFilterMode.range,
                  onSelected: (_) =>
                      onDateFilterModeChanged(ExpenseDateFilterMode.range),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.event),
              label: Text(
                dateFilterMode == ExpenseDateFilterMode.single
                    ? singleLabel
                    : rangeLabel,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                VN.expenseCategoryLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text(VN.filterAll),
                      selected: filterCategory.isEmpty,
                      onSelected: (_) => onFilterCategoryChanged(''),
                    ),
                  ),
                  ...categories
                      .map(
                        (category) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: filterCategory == category,
                            onSelected: (_) => onFilterCategoryChanged(category),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                VN.expenseFilterStaffLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text(VN.filterAll),
                      selected: filterStaffName.isEmpty,
                      onSelected: (_) => onFilterStaffChanged(''),
                    ),
                  ),
                  ...staffNames
                      .map(
                        (staffName) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(staffName),
                            selected: filterStaffName == staffName,
                            onSelected: (_) => onFilterStaffChanged(staffName),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClearFilters,
                    child: const Text(VN.expenseResetFiltersAction),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onApplyFilters,
                    child: const Text(VN.expenseApplyFiltersAction),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
