import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/data/models/knowledge_entry.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/categories/providers/category_form_notifier.dart';
import 'package:bakery_app/features/blanks/providers/blank_form_notifier.dart';
import 'package:bakery_app/features/customers/providers/customer_form_notifier.dart';
import 'package:bakery_app/features/events/providers/event_log_form_notifier.dart';
import 'package:bakery_app/features/expenses/providers/debt_settlement_notifier.dart';
import 'package:bakery_app/features/expenses/providers/expense_form_notifier.dart';
import 'package:bakery_app/features/knowledge/providers/knowledge_form_notifier.dart';
import 'package:bakery_app/features/products/providers/product_form_notifier.dart';
import 'package:bakery_app/features/templates/providers/template_editor_notifier.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('category create and edit entities retain and clear independently', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const create = FormDraftContext(
      formType: 'category',
      mode: FormDraftMode.create,
    );
    const editA = FormDraftContext(
      formType: 'category',
      mode: FormDraftMode.edit,
      entityId: '7',
    );
    const editB = FormDraftContext(
      formType: 'category',
      mode: FormDraftMode.edit,
      entityId: '8',
    );

    container.read(contextualCategoryFormProvider(create).notifier)
      ..seed()
      ..updateNewDraft(name: 'Tao moi', slug: 'tao_moi')
      ..setSelectedIcon('A');
    container.read(contextualCategoryFormProvider(editA).notifier)
      ..seed(
        editingId: 7,
        name: 'Danh muc A',
        codePrefix: 'DA',
        slug: 'danh_muc_a',
      )
      ..updateNewDraft(name: 'Sua A')
      ..setSelectedIcon('B');

    expect(
      container
          .read(contextualCategoryFormProvider(create).notifier)
          .newDraft
          .name,
      'Tao moi',
    );
    expect(
      container
          .read(contextualCategoryFormProvider(editA).notifier)
          .newDraft
          .name,
      'Sua A',
    );
    expect(
      container
          .read(contextualCategoryFormProvider(editB).notifier)
          .newDraft
          .name,
      isEmpty,
    );

    container.invalidate(contextualCategoryFormProvider(editA));
    expect(
      container.read(contextualCategoryFormProvider(editA)).selectedIcon,
      'B',
    );
    container
        .read(contextualCategoryFormProvider(editA).notifier)
        .clearNewDraft();
    expect(
      container.read(formDraftSessionProvider).containsKey(editA),
      isFalse,
    );
    expect(
      container.read(formDraftSessionProvider).containsKey(create),
      isTrue,
    );
  });

  test('expense contexts preserve photos and explicit nullable clears', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const editA = FormDraftContext(
      formType: 'expense',
      mode: FormDraftMode.edit,
      entityId: '10',
    );
    const editB = FormDraftContext(
      formType: 'expense',
      mode: FormDraftMode.edit,
      entityId: '11',
    );
    final a = container.read(contextualExpenseFormProvider(editA).notifier);
    a
      ..startNew()
      ..setAmount('120000')
      ..setCategory('materials')
      ..setSubcategory('flour')
      ..setSubcategory(null)
      ..setSelectedPhotos([XFile('/tmp/expense-a.jpg')])
      ..setLoading(true)
      ..setLoading(false);

    container.invalidate(contextualExpenseFormProvider(editA));
    final restored = container.read(contextualExpenseFormProvider(editA));
    expect(restored.newDraft.amount, '120000');
    expect(restored.subcategory, isNull);
    expect(restored.selectedPhotos.single.path, '/tmp/expense-a.jpg');
    expect(restored.loading, isFalse);
    expect(
      container.read(contextualExpenseFormProvider(editB)).selectedPhotos,
      isEmpty,
    );
  });

  test(
    'quick-log operation state is transient and success clears its draft',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const context = FormDraftContext(
        formType: 'event-quick-log',
        mode: FormDraftMode.create,
      );
      final provider = contextualEventLogFormProvider(context);
      final notifier = container.read(provider.notifier);
      notifier
        ..setSummary('Kiem tra lo nuong')
        ..setSelectedPhotos([XFile('/tmp/oven.jpg')])
        ..setSaving(true)
        ..setSaving(false);

      container.invalidate(provider);
      final restored = container.read(provider);
      expect(restored.summary, 'Kiem tra lo nuong');
      expect(restored.selectedPhotos.single.path, '/tmp/oven.jpg');
      expect(restored.saving, isFalse);

      container.read(provider.notifier).reset();
      expect(
        container.read(formDraftSessionProvider).containsKey(context),
        isFalse,
      );
    },
  );

  test(
    'product photo copyWith supports explicit null and contexts isolate',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const create = FormDraftContext(
        formType: 'product',
        mode: FormDraftMode.create,
      );
      const edit = FormDraftContext(
        formType: 'product',
        mode: FormDraftMode.edit,
        entityId: '5',
      );
      final createNotifier = container.read(
        contextualProductFormProvider(create).notifier,
      );
      createNotifier
        ..updateNewDraft(name: 'Banh A')
        ..setPickedPhoto(XFile('/tmp/product.jpg'))
        ..setPickedPhoto(null);

      expect(
        container.read(contextualProductFormProvider(create)).pickedPhoto,
        isNull,
      );
      expect(
        container.read(contextualProductFormProvider(edit)).pickedPhoto,
        isNull,
      );
      expect(
        container
            .read(formDraftSessionProvider.notifier)
            .readDraft<ProductNewDraft>(create)
            ?.pickedPhoto,
        isNull,
      );
    },
  );

  test('stale category completion preserves a newer reopened draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const context = FormDraftContext(
      formType: 'category',
      mode: FormDraftMode.create,
    );
    final notifier = container.read(
      contextualCategoryFormProvider(context).notifier,
    );
    notifier
      ..seed()
      ..updateNewDraft(name: 'Submitted');
    final submitted = notifier.draftSnapshot;

    notifier.updateNewDraft(name: 'Newer draft');

    expect(notifier.clearAfterSuccess(submitted), isFalse);
    expect(notifier.newDraft.name, 'Newer draft');
    expect(
      container.read(formDraftSessionProvider).containsKey(context),
      isTrue,
    );
  });

  test('session clear resets live contextual notifier state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const context = FormDraftContext(
      formType: 'product',
      mode: FormDraftMode.edit,
      entityId: '17',
    );
    final provider = contextualProductFormProvider(context);
    final notifier = container.read(provider.notifier);
    notifier
      ..updateNewDraft(name: 'User A draft')
      ..setRutTien(true)
      ..setPickedPhoto(XFile('/tmp/user-a.jpg'));

    container.read(formDraftSessionProvider.notifier).clearAll();
    await container.pump();

    final nextSession = container.read(provider);
    expect(container.read(provider.notifier).newDraft.name, isEmpty);
    expect(nextSession.rutTien, isFalse);
    expect(nextSession.pickedPhoto, isNull);
    expect(container.read(formDraftSessionProvider), isEmpty);
  });

  test('template failure restores only its context and success clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const personal = FormDraftContext(
      formType: 'template',
      mode: FormDraftMode.create,
      variantId: 'false',
    );
    const system = FormDraftContext(
      formType: 'template',
      mode: FormDraftMode.create,
      variantId: 'true',
    );
    const edit = FormDraftContext(
      formType: 'template',
      mode: FormDraftMode.edit,
      entityId: '21',
    );
    final provider = contextualTemplateEditorProvider(personal);
    final notifier = container.read(provider.notifier);
    notifier
      ..seed(null, initialIsSystem: false)
      ..updateNewDraft(name: 'Dang soan', body: 'Noi dung loi')
      ..setSelectedScenario('follow_up')
      ..setSaving(true)
      ..setSaving(false);

    container.invalidate(provider);
    final restored = container.read(provider);
    final restoredNotifier = container.read(provider.notifier);
    expect(restoredNotifier.newDraft.name, 'Dang soan');
    expect(restoredNotifier.newDraft.body, 'Noi dung loi');
    expect(restored.selectedScenario, 'follow_up');
    expect(restored.saving, isFalse);
    expect(
      container
          .read(contextualTemplateEditorProvider(system).notifier)
          .newDraft
          .name,
      isEmpty,
    );
    expect(
      container
          .read(contextualTemplateEditorProvider(edit).notifier)
          .newDraft
          .name,
      isEmpty,
    );

    final submitted = restoredNotifier.draftSnapshot;
    expect(restoredNotifier.clearAfterSuccess(submitted), isTrue);
    expect(
      container.read(formDraftSessionProvider).containsKey(personal),
      isFalse,
    );
  });

  test('template edit mutation retains its complete seeded baseline', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const context = FormDraftContext(
      formType: 'template',
      mode: FormDraftMode.edit,
      entityId: '22',
    );
    final provider = contextualTemplateEditorProvider(context);
    final notifier = container.read(provider.notifier);
    notifier
      ..seed(
        const MessageTemplate(
          id: 22,
          scenario: 'payment_request',
          name: 'Baseline name',
          body: 'Baseline body',
          isSystem: true,
          active: false,
        ),
        initialIsSystem: true,
      )
      ..updateNewDraft(name: 'Mutated name');

    container.invalidate(provider);
    final restored = container.read(provider);
    final draft = container.read(provider.notifier).newDraft;
    expect(restored.editingId, 22);
    expect(draft.name, 'Mutated name');
    expect(draft.body, 'Baseline body');
    expect(draft.scenario, 'payment_request');
    expect(draft.isActive, isFalse);
    expect(draft.isSystem, isTrue);
  });

  test(
    'customer failure restores one entity and confirmed discard clears it',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const editA = FormDraftContext(
        formType: 'customer',
        mode: FormDraftMode.edit,
        entityId: '31',
      );
      const editB = FormDraftContext(
        formType: 'customer',
        mode: FormDraftMode.edit,
        entityId: '32',
      );
      final provider = contextualCustomerFormProvider(editA);
      final notifier = container.read(provider.notifier);
      notifier
        ..initialize(
          const CustomerFormDraft(
            name: 'Khach cu',
            phones: [CustomerPhone(phone: '0900000000', isPrimary: true)],
          ),
        )
        ..updateNewDraft(
          name: 'Khach dang sua',
          phones: const [
            CustomerPhone(phone: '0911111111', isPrimary: true),
            CustomerPhone(phone: '0922222222'),
          ],
        )
        ..startSubmit()
        ..clearSaving();

      container.invalidate(provider);
      final restored = container.read(provider);
      expect(restored.newDraft.name, 'Khach dang sua');
      expect(restored.newDraft.phones, hasLength(2));
      expect(restored.newDraft.phones.first.phone, '0911111111');
      expect(restored.saving, isFalse);
      expect(
        container.read(contextualCustomerFormProvider(editB)).newDraft.name,
        isEmpty,
      );

      container.read(provider.notifier).clearNewDraft();
      expect(
        container.read(formDraftSessionProvider).containsKey(editA),
        isFalse,
      );
    },
  );

  test(
    'debt failure restores one action and success clears submitted draft',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const debtA = FormDraftContext(
        formType: 'debt-settlement',
        mode: FormDraftMode.action,
        entityId: '41',
      );
      const debtB = FormDraftContext(
        formType: 'debt-settlement',
        mode: FormDraftMode.action,
        entityId: '42',
      );
      final provider = contextualDebtSettlementProvider(debtA);
      final notifier = container.read(provider.notifier);
      notifier
        ..setAmount('250000')
        ..setNote('Thanh toan lan mot')
        ..setPaymentMethod('Chuyen khoan')
        ..setPaymentSource('Tai khoan ngan hang')
        ..setSubmitting(true)
        ..setSubmitting(false);

      container.invalidate(provider);
      final restored = container.read(provider);
      final restoredNotifier = container.read(provider.notifier);
      expect(restoredNotifier.draft.amount, '250000');
      expect(restoredNotifier.draft.note, 'Thanh toan lan mot');
      expect(restored.paymentMethod, 'Chuyen khoan');
      expect(restored.paymentSource, 'Tai khoan ngan hang');
      expect(restored.submitting, isFalse);
      expect(
        container
            .read(contextualDebtSettlementProvider(debtB).notifier)
            .draft
            .amount,
        isEmpty,
      );

      final submitted = restoredNotifier.draftSnapshot;
      expect(restoredNotifier.clearAfterSuccess(submitted), isTrue);
      expect(
        container.read(formDraftSessionProvider).containsKey(debtA),
        isFalse,
      );
    },
  );

  test(
    'blank edit failure restores in context and session epoch clears it',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const editA = FormDraftContext(
        formType: 'blank',
        mode: FormDraftMode.edit,
        entityId: '51',
      );
      const editB = FormDraftContext(
        formType: 'blank',
        mode: FormDraftMode.edit,
        entityId: '52',
      );
      final provider = contextualBlankFormProvider(editA);
      final notifier = container.read(provider.notifier);
      notifier
        ..seed(
          const Blank(id: 51, name: 'Phoi cu', category: 'cot', unit: 'kg'),
        )
        ..updateNewDraft(name: 'Phoi dang sua', unit: 'cai', notes: 'Chua xong')
        ..setCategory('kem')
        ..setSaving(true)
        ..setSaving(false);

      container.invalidate(provider);
      final restored = container.read(provider);
      final restoredNotifier = container.read(provider.notifier);
      expect(restored.editing, isTrue);
      expect(restoredNotifier.newDraft.name, 'Phoi dang sua');
      expect(restoredNotifier.newDraft.unit, 'cai');
      expect(restoredNotifier.newDraft.notes, 'Chua xong');
      expect(restored.category, 'kem');
      expect(restored.saving, isFalse);
      expect(
        container
            .read(contextualBlankFormProvider(editB).notifier)
            .newDraft
            .name,
        isEmpty,
      );

      container.read(formDraftSessionProvider.notifier).clearAll();
      await container.pump();
      expect(container.read(provider.notifier).newDraft.name, isEmpty);
      expect(container.read(formDraftSessionProvider), isEmpty);
    },
  );

  test(
    'knowledge edit failure restores media and confirmed discard clears it',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const editA = FormDraftContext(
        formType: 'knowledge',
        mode: FormDraftMode.edit,
        entityId: '61',
      );
      const editB = FormDraftContext(
        formType: 'knowledge',
        mode: FormDraftMode.edit,
        entityId: '62',
      );
      final timestamp = DateTime(2026, 8, 24);
      final provider = contextualKnowledgeFormProvider(editA);
      final notifier = container.read(provider.notifier);
      notifier
        ..seed(
          KnowledgeEntry(
            id: 61,
            title: 'Cong thuc cu',
            content: 'Noi dung cu',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        )
        ..updateNewDraft(title: 'Cong thuc dang sua', content: 'Chua xong')
        ..setSelectedType('recipe')
        ..addTag('banh-mi')
        ..setPinAfterSave(true)
        ..addPhotos([
          KnowledgeFormPhotoEntry(file: XFile('/tmp/knowledge-draft.jpg')),
        ])
        ..setSaving(true)
        ..setSaving(false);

      container.invalidate(provider);
      final restored = container.read(provider);
      final restoredNotifier = container.read(provider.notifier);
      expect(restored.editing, isTrue);
      expect(restoredNotifier.newDraft.title, 'Cong thuc dang sua');
      expect(restoredNotifier.newDraft.content, 'Chua xong');
      expect(restored.selectedType, 'recipe');
      expect(restored.selectedTags, contains('banh-mi'));
      expect(restored.pinAfterSave, isTrue);
      expect(restored.photos.single.file?.path, '/tmp/knowledge-draft.jpg');
      expect(restored.saving, isFalse);
      expect(
        container
            .read(contextualKnowledgeFormProvider(editB).notifier)
            .newDraft
            .title,
        isEmpty,
      );

      restoredNotifier.clearNewDraft();
      expect(
        container.read(formDraftSessionProvider).containsKey(editA),
        isFalse,
      );
    },
  );
}
