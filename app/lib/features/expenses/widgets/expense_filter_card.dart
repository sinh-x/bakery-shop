import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';

class ExpenseFilterCard extends StatelessWidget {
  const ExpenseFilterCard({
    super.key,
    required this.searchCtrl,
    required this.filterStaffCtrl,
    required this.since,
    required this.until,
    required this.categories,
    required this.paymentMethods,
    required this.filterCategory,
    required this.filterPaymentMethod,
    required this.onPickSince,
    required this.onPickUntil,
    required this.onFilterCategoryChanged,
    required this.onFilterPaymentMethodChanged,
    required this.onFilterStaffChanged,
    required this.onClearFilters,
    required this.onApplyFilters,
    required this.formatDate,
  });

  final TextEditingController searchCtrl;
  final TextEditingController filterStaffCtrl;
  final DateTime? since;
  final DateTime? until;
  final List<String> categories;
  final List<String> paymentMethods;
  final String filterCategory;
  final String filterPaymentMethod;
  final VoidCallback onPickSince;
  final VoidCallback onPickUntil;
  final ValueChanged<String?> onFilterCategoryChanged;
  final ValueChanged<String?> onFilterPaymentMethodChanged;
  final ValueChanged<String> onFilterStaffChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onApplyFilters;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPickSince,
                    child: Text(
                      since == null ? VN.expenseSinceLabel : formatDate(since!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPickUntil,
                    child: Text(
                      until == null ? VN.expenseUntilLabel : formatDate(until!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: filterCategory,
              decoration: const InputDecoration(
                labelText: VN.expenseCategoryLabel,
                border: OutlineInputBorder(),
              ),
              items: <String>['', ...categories]
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.isEmpty ? VN.filterAll : item),
                    ),
                  )
                  .toList(),
              onChanged: onFilterCategoryChanged,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: filterPaymentMethod,
              decoration: const InputDecoration(
                labelText: VN.expensePaymentMethodLabel,
                border: OutlineInputBorder(),
              ),
              items: <String>['', ...paymentMethods]
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.isEmpty ? VN.filterAll : item),
                    ),
                  )
                  .toList(),
              onChanged: onFilterPaymentMethodChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: filterStaffCtrl,
              decoration: const InputDecoration(
                labelText: VN.expenseFilterStaffLabel,
                border: OutlineInputBorder(),
              ),
              onChanged: onFilterStaffChanged,
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
