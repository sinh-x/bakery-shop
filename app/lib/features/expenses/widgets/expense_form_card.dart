import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
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

  bool get _isDebt => widget.paymentMethod == VN.methodDebt;

  @override
  Widget build(BuildContext context) {
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
                  labelText: VN.expenseAmountLabel,
                  border: OutlineInputBorder(),
                ),
                validator: widget.amountValidator,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.category,
                decoration: const InputDecoration(
                  labelText: VN.expenseCategoryLabel,
                  hintText: VN.expenseCategoryHint,
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
                    (value == null || value.isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.paymentMethod,
                decoration: const InputDecoration(
                  labelText: VN.expensePaymentMethodLabel,
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
                    labelText: VN.expensePaymentSourceLabel,
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
                      (value == null || value.isEmpty) ? VN.fieldRequired : null,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onPickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        '${VN.expenseDateLabel}: '
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
                        '${VN.expenseTimeLabel}: '
                        '${formatDisplayTime(widget.eventDateTime)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isDebt)
                _buildCreditorField()
              else
                TextFormField(
                  controller: widget.vendorCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.expenseVendorLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: VN.expenseNoteLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.staffList.contains(widget.selectedPaidByName)
                    ? widget.selectedPaidByName
                    : null,
                decoration: const InputDecoration(
                  labelText: VN.expensePaidByNameLabel,
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
                      child: const Text(VN.expenseCancelEditAction),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.loading ? null : widget.onSave,
                      child: Text(
                        widget.editing
                            ? VN.expenseUpdateAction
                            : VN.expenseSaveAction,
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

  Widget _buildCreditorField() {
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
          decoration: const InputDecoration(
            labelText: VN.expenseCreditorLabel,
            hintText: VN.expenseVendorAutocompleteHint,
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              (value == null || value.trim().isEmpty)
                  ? VN.expenseDebtVendorRequired
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
