import 'package:bakery_app/data/models/expense_category.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';

class ExpenseFormCard extends StatefulWidget {
  const ExpenseFormCard({
    super.key,
    required this.formKey,
    required this.amountCtrl,
    required this.vendorCtrl,
    required this.noteCtrl,
    required this.eventDateTime,
    required this.categories,
    required this.paymentMethods,
    required this.paymentSources,
    required this.staffList,
    required this.category,
    required this.paymentMethod,
    required this.paymentSource,
    required this.selectedPaidByName,
    required this.loading,
    required this.editing,
    required this.onCategoryChanged,
    required this.onPaymentMethodChanged,
    required this.onPaymentSourceChanged,
    required this.onPaidByNameChanged,
    required this.onPickDate,
    required this.onPickTime,
    required this.onCancelEdit,
    required this.onSave,
    required this.amountValidator,
    this.vendorSuggestions = const <String>[],
    this.categoryTree = const <ExpenseCategory>[],
    this.subcategory,
    this.onSubcategoryChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController amountCtrl;
  final TextEditingController vendorCtrl;
  final TextEditingController noteCtrl;
  final DateTime eventDateTime;
  final List<String> categories;
  final List<String> paymentMethods;
  final List<String> paymentSources;
  final List<String> staffList;
  final String? category;
  final String paymentMethod;
  final String paymentSource;
  final String? selectedPaidByName;
  final bool loading;
  final bool editing;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final ValueChanged<String?> onPaymentSourceChanged;
  final ValueChanged<String?> onPaidByNameChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onCancelEdit;
  final VoidCallback onSave;
  final String? Function(String?) amountValidator;

  /// Autocomplete options for the vendor field, sourced from previously
  /// recorded expense vendors (DG-212 Phase 3 — FR2).
  final List<String> vendorSuggestions;

  /// Loaded expense category tree (DG-302 Phase 4 — FR1/FR5). Used to
  /// look up the subcategories of the selected parent category. Empty for
  /// callers that have not opted in (preserves existing behavior).
  final List<ExpenseCategory> categoryTree;

  /// Currently selected subcategory name (empty/null when none selected).
  final String? subcategory;

  /// Callback invoked when the subcategory dropdown changes. When null,
  /// the subcategory dropdown is not rendered even if the category has
  /// children (preserves existing behavior for callers that did not opt
  /// in).
  final ValueChanged<String?>? onSubcategoryChanged;

  @override
  State<ExpenseFormCard> createState() => _ExpenseFormCardState();
}

class _ExpenseFormCardState extends State<ExpenseFormCard> {
  late final FocusNode _vendorFocusNode;

  @override
  void initState() {
    super.initState();
    _vendorFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _vendorFocusNode.dispose();
    super.dispose();
  }

  bool get _isDebt => widget.paymentMethod == OrdersLabels.methodDebt;

  /// Subcategory names available for the currently selected category
  /// (DG-302 Phase 4 — FR1). Empty when the category has no children or
  /// when no category is selected. The dropdown is only rendered when
  /// this list is non-empty AND an [onSubcategoryChanged] callback is
  /// provided (FR6 backward compat — callers that have not opted in keep
  /// the legacy single-dropdown behavior).
  List<String> get _subcategoryOptions {
    final category = widget.category;
    if (category == null || category.isEmpty) return const <String>[];
    if (widget.onSubcategoryChanged == null) return const <String>[];
    return widget.categoryTree.subcategoriesOf(category).map((c) => c.name).toList();
  }

  @override
  Widget build(BuildContext context) {
    final subcategoryOptions = _subcategoryOptions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: widget.formKey,
          child: Column(
            children: [
              TextFormField(
                controller: widget.amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: ExpensesLabels.expenseAmountLabel,
                  border: OutlineInputBorder(),
                ),
                validator: widget.amountValidator,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.category,
                decoration: const InputDecoration(
                  labelText: ExpensesLabels.expenseCategoryLabel,
                  hintText: ExpensesLabels.expenseCategoryHint,
                  border: OutlineInputBorder(),
                ),
                items: widget.categories
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: widget.onCategoryChanged,
                validator: (value) =>
                    (value == null || value.isEmpty) ? SharedLabels.fieldRequired : null,
              ),
              const SizedBox(height: 8),
              if (subcategoryOptions.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: widget.subcategory,
                  decoration: const InputDecoration(
                    labelText: ExpensesLabels.expenseSubcategoryLabel,
                    hintText: ExpensesLabels.expenseSubcategoryHint,
                    border: OutlineInputBorder(),
                  ),
                  items: subcategoryOptions
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: widget.onSubcategoryChanged,
                  validator: (value) =>
                      (value == null || value.isEmpty) ? SharedLabels.fieldRequired : null,
                ),
              if (subcategoryOptions.isNotEmpty) const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.paymentMethod,
                decoration: const InputDecoration(
                  labelText: ExpensesLabels.expensePaymentMethodLabel,
                  border: OutlineInputBorder(),
                ),
                items: widget.paymentMethods
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: widget.onPaymentMethodChanged,
              ),
              const SizedBox(height: 8),
              if (!_isDebt)
                DropdownButtonFormField<String>(
                  initialValue: widget.paymentSource,
                  decoration: const InputDecoration(
                    labelText: ExpensesLabels.expensePaymentSourceLabel,
                    border: OutlineInputBorder(),
                  ),
                  items: widget.paymentSources
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: widget.onPaymentSourceChanged,
                  validator: (value) =>
                      (value == null || value.isEmpty) ? SharedLabels.fieldRequired : null,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onPickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        '${ExpensesLabels.expenseDateLabel}: '
                        '${formatDisplayDate(widget.eventDateTime)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onPickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        '${ExpensesLabels.expenseTimeLabel}: '
                        '${formatDisplayTime(widget.eventDateTime)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildVendorField(),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: ExpensesLabels.expenseNoteLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.staffList.contains(widget.selectedPaidByName)
                    ? widget.selectedPaidByName
                    : null,
                decoration: const InputDecoration(
                  labelText: ExpensesLabels.expensePaidByNameLabel,
                  border: OutlineInputBorder(),
                ),
                items: widget.staffList
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: widget.onPaidByNameChanged,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.editing ? widget.onCancelEdit : null,
                      child: const Text(ExpensesLabels.expenseCancelEditAction),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.loading ? null : widget.onSave,
                      child: Text(
                        widget.editing
                            ? ExpensesLabels.expenseUpdateAction
                            : ExpensesLabels.expenseSaveAction,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendorField() {
    return RawAutocomplete<String>(
      textEditingController: widget.vendorCtrl,
      focusNode: _vendorFocusNode,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return widget.vendorSuggestions.take(20);
        return widget.vendorSuggestions
            .where((name) => name.toLowerCase().contains(query))
            .take(20);
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: _isDebt
                ? ExpensesLabels.expenseCreditorLabel
                : ExpensesLabels.expenseVendorLabel,
            hintText: ExpensesLabels.expenseVendorAutocompleteHint,
            suffixIcon: const Icon(Icons.arrow_drop_down),
            border: const OutlineInputBorder(),
          ),
          validator: _isDebt
              ? (value) =>
                  (value == null || value.trim().isEmpty)
                      ? ExpensesLabels.expenseDebtVendorRequired
                      : null
              : null,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options
                    .map((option) => ListTile(
                          dense: true,
                          title: Text(option),
                          onTap: () => onSelected(option),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
