import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';

class ExpenseFormCard extends StatelessWidget {
  const ExpenseFormCard({
    super.key,
    required this.formKey,
    required this.amountCtrl,
    required this.vendorCtrl,
    required this.noteCtrl,
    required this.staffCtrl,
    required this.categories,
    required this.paymentMethods,
    required this.category,
    required this.paymentMethod,
    required this.loading,
    required this.editing,
    required this.onCategoryChanged,
    required this.onPaymentMethodChanged,
    required this.onCancelEdit,
    required this.onSave,
    required this.amountValidator,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController amountCtrl;
  final TextEditingController vendorCtrl;
  final TextEditingController noteCtrl;
  final TextEditingController staffCtrl;
  final List<String> categories;
  final List<String> paymentMethods;
  final String? category;
  final String paymentMethod;
  final bool loading;
  final bool editing;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
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
              TextFormField(
                controller: staffCtrl,
                decoration: const InputDecoration(
                  labelText: VN.expenseStaffNameLabel,
                  border: OutlineInputBorder(),
                ),
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
