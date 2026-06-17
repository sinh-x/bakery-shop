import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';

class ExpenseFormCard extends StatelessWidget {
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
    required this.selectedStaffName,
    required this.selectedPaidByName,
    required this.loading,
    required this.editing,
    required this.onCategoryChanged,
    required this.onPaymentMethodChanged,
    required this.onPaymentSourceChanged,
    required this.onStaffChanged,
    required this.onPaidByNameChanged,
    required this.onPickDate,
    required this.onPickTime,
    required this.onCancelEdit,
    required this.onSave,
    required this.amountValidator,
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
  final String? selectedStaffName;
  final String? selectedPaidByName;
  final bool loading;
  final bool editing;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final ValueChanged<String?> onPaymentSourceChanged;
  final ValueChanged<String?> onStaffChanged;
  final ValueChanged<String?> onPaidByNameChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onCancelEdit;
  final VoidCallback onSave;
  final String? Function(String?) amountValidator;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: VN.expenseAmountLabel,
                  border: OutlineInputBorder(),
                ),
                validator: amountValidator,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: VN.expenseCategoryLabel,
                  hintText: VN.expenseCategoryHint,
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onCategoryChanged,
                validator: (value) =>
                    (value == null || value.isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(
                  labelText: VN.expensePaymentMethodLabel,
                  border: OutlineInputBorder(),
                ),
                items: paymentMethods
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onPaymentMethodChanged,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: paymentSource,
                decoration: const InputDecoration(
                  labelText: VN.expensePaymentSourceLabel,
                  border: OutlineInputBorder(),
                ),
                items: paymentSources
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onPaymentSourceChanged,
                validator: (value) =>
                    (value == null || value.isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        '${VN.expenseDateLabel}: '
                        '${eventDateTime.day.toString().padLeft(2, '0')}/'
                        '${eventDateTime.month.toString().padLeft(2, '0')}/'
                        '${eventDateTime.year}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        '${VN.expenseTimeLabel}: '
                        '${eventDateTime.hour.toString().padLeft(2, '0')}:'
                        '${eventDateTime.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: vendorCtrl,
                decoration: const InputDecoration(
                  labelText: VN.expenseVendorLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: VN.expenseNoteLabel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: staffList.contains(selectedStaffName)
                    ? selectedStaffName
                    : null,
                decoration: const InputDecoration(
                  labelText: VN.expenseStaffNameLabel,
                  border: OutlineInputBorder(),
                ),
                items: staffList
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onStaffChanged,
                validator: (value) =>
                    (value == null || value.isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: staffList.contains(selectedPaidByName)
                    ? selectedPaidByName
                    : null,
                decoration: const InputDecoration(
                  labelText: VN.expensePaidByNameLabel,
                  border: OutlineInputBorder(),
                ),
                items: staffList
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onPaidByNameChanged,
                validator: (value) =>
                    (value == null || value.isEmpty) ? VN.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: editing ? onCancelEdit : null,
                      child: const Text(VN.expenseCancelEditAction),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: loading ? null : onSave,
                      child: Text(
                        editing ? VN.expenseUpdateAction : VN.expenseSaveAction,
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
}
