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
    required this.paymentSources,
    required this.paidByNames,
    required this.loggedByNames,
    required this.filterCategory,
    required this.filterPaymentSource,
    required this.filterPaidByName,
    required this.filterLoggedByName,
    required this.onDateFilterModeChanged,
    required this.onPickDate,
    required this.onFilterCategoryChanged,
    required this.onFilterPaymentSourceChanged,
    required this.onFilterPaidByNameChanged,
    required this.onFilterLoggedByNameChanged,
    required this.onClearFilters,
    required this.onApplyFilters,
    required this.formatDate,
  });

  final TextEditingController searchCtrl;
  final DateTime? since;
  final DateTime? until;
  final ExpenseDateFilterMode dateFilterMode;
  final List<String> categories;
  final List<String> paymentSources;
  final List<String> paidByNames;
  final List<String> loggedByNames;
  final String filterCategory;
  final String filterPaymentSource;
  final String filterPaidByName;
  final String filterLoggedByName;
  final ValueChanged<ExpenseDateFilterMode> onDateFilterModeChanged;
  final VoidCallback onPickDate;
  final ValueChanged<String> onFilterCategoryChanged;
  final ValueChanged<String> onFilterPaymentSourceChanged;
  final ValueChanged<String> onFilterPaidByNameChanged;
  final ValueChanged<String> onFilterLoggedByNameChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onApplyFilters;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeLabel = since == null || until == null
        ? VN.lichSuDonHangLocKhoangNgay
        : '${formatDate(since!)} - ${formatDate(until!)}';
    final singleLabel = since == null
        ? VN.expenseSinceLabel
        : formatDate(since!);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                labelText: VN.expenseSearchLabel,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPickDate,
              child: Ink(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dateFilterMode == ExpenseDateFilterMode.single
                              ? singleLabel
                              : rangeLabel,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FilterChipStrip(
              label: VN.expenseCategoryLabel,
              chips: [
                FilterChip(
                  label: const Text(VN.filterAll),
                  selected: filterCategory.isEmpty,
                  onSelected: (_) => onFilterCategoryChanged(''),
                  visualDensity: VisualDensity.compact,
                ),
                ...categories.map(
                  (category) => FilterChip(
                    label: Text(category),
                    selected: filterCategory == category,
                    onSelected: (_) => onFilterCategoryChanged(category),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _FilterChipStrip(
              label: VN.expensePaymentSourceLabel,
              chips: [
                FilterChip(
                  label: const Text(VN.filterAll),
                  selected: filterPaymentSource.isEmpty,
                  onSelected: (_) => onFilterPaymentSourceChanged(''),
                  visualDensity: VisualDensity.compact,
                ),
                ...paymentSources.map(
                  (source) => FilterChip(
                    label: Text(source),
                    selected: filterPaymentSource == source,
                    onSelected: (_) => onFilterPaymentSourceChanged(source),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _FilterChipStrip(
              label: VN.expensePaidByNameLabel,
              chips: [
                FilterChip(
                  label: const Text(VN.filterAll),
                  selected: filterPaidByName.isEmpty,
                  onSelected: (_) => onFilterPaidByNameChanged(''),
                  visualDensity: VisualDensity.compact,
                ),
                ...paidByNames.map(
                  (name) => FilterChip(
                    label: Text(name),
                    selected: filterPaidByName == name,
                    onSelected: (_) => onFilterPaidByNameChanged(name),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _FilterChipStrip(
              label: VN.expenseLoggedByLabel,
              chips: [
                FilterChip(
                  label: const Text(VN.filterAll),
                  selected: filterLoggedByName.isEmpty,
                  onSelected: (_) => onFilterLoggedByNameChanged(''),
                  visualDensity: VisualDensity.compact,
                ),
                ...loggedByNames.map(
                  (name) => FilterChip(
                    label: Text(name),
                    selected: filterLoggedByName == name,
                    onSelected: (_) => onFilterLoggedByNameChanged(name),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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

class _FilterChipStrip extends StatelessWidget {
  const _FilterChipStrip({required this.label, required this.chips});

  final String label;
  final List<Widget> chips;

  static const _labelWidth = 92.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 9),
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ...chips.map(
            (chip) =>
                Padding(padding: const EdgeInsets.only(right: 6), child: chip),
          ),
        ],
      ),
    );
  }
}
