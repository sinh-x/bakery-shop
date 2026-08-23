import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/providers/expense_form_notifier.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test(
    'expense edit restores text, selections, and photos only in context',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const context = FormDraftContext(
        formType: 'expense',
        mode: FormDraftMode.edit,
        entityId: '42',
      );
      const other = FormDraftContext(
        formType: 'expense',
        mode: FormDraftMode.edit,
        entityId: '43',
      );
      final provider = contextualExpenseFormProvider(context);
      final notifier = container.read(provider.notifier);

      notifier
        ..startEdit(
          event: BakeryEvent(
            id: 42,
            timestamp: DateTime(2026, 8, 20),
            summary: 'Edited expense',
          ),
          staffName: 'Lan',
        )
        ..initializeEditFields(
          amount: '100000',
          vendor: 'NCC goc',
          note: 'Ghi chu goc',
          category: ExpensesLabels.expenseCategoryIngredient,
          subcategory: null,
          paymentMethod: 'Tiền mặt',
          paymentSource: 'Tiền mặt két',
          paidByName: 'Lan',
        )
        ..setAmount('125000')
        ..setVendor('NCC A')
        ..setNote('Bột mì')
        ..setSelectedPhotos([XFile('/tmp/new-expense.jpg')]);

      container.invalidate(provider);
      final reopened = container.read(provider);
      expect(reopened.editingId, 42);
      expect(reopened.newDraft.amount, '125000');
      expect(reopened.newDraft.vendor, 'NCC A');
      expect(reopened.newDraft.note, 'Bột mì');
      expect(reopened.category, ExpensesLabels.expenseCategoryIngredient);
      expect(reopened.selectedPhotos.single.path, '/tmp/new-expense.jpg');
      expect(
        container.read(contextualExpenseFormProvider(other)).selectedPhotos,
        isEmpty,
      );
    },
  );

  test('successful NEW expense reset clears every draft value', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(expenseFormProvider.notifier);

    notifier
      ..setAmount('50000')
      ..setVendor('Vendor')
      ..setNote('Note')
      ..setCategory(ExpensesLabels.expenseCategoryOther)
      ..setPaidByName('Lan')
      ..clearNewDraft(staffName: 'Lan');

    final cleared = container.read(expenseFormProvider);
    expect(cleared.editingId, isNull);
    expect(cleared.category, isNull);
    expect(cleared.paidByName, isNull);
    expect(cleared.newDraft.amount, isEmpty);
    expect(cleared.newDraft.vendor, isEmpty);
    expect(cleared.newDraft.note, isEmpty);
    expect(cleared.selectedPhotos, isEmpty);
  });
}
