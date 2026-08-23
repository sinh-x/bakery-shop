import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/blanks/providers/blank_form_notifier.dart';
import 'package:bakery_app/features/categories/providers/category_form_notifier.dart';
import 'package:bakery_app/features/knowledge/providers/knowledge_form_notifier.dart';
import 'package:bakery_app/features/products/providers/product_form_notifier.dart';
import 'package:bakery_app/features/templates/providers/template_editor_notifier.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('product create context retains fields and photo in isolation', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const create = FormDraftContext(
      formType: 'product',
      mode: FormDraftMode.create,
    );
    const edit = FormDraftContext(
      formType: 'product',
      mode: FormDraftMode.edit,
      entityId: '7',
    );
    final provider = contextualProductFormProvider(create);
    final notifier = container.read(provider.notifier);

    notifier.seed(initialCategory: 'bread');
    notifier.updateNewDraft(
      name: 'Banh moi',
      price: '12000',
      priceChips: const [ProductPriceChipDraft(label: 'Nho', price: '10000')],
    );
    notifier.setCategory('bread');
    notifier.setRutTien(true);
    notifier.setPickedPhoto(XFile('/tmp/product.jpg'));
    container.invalidate(provider);
    final reopenedNotifier = container.read(provider.notifier);

    expect(reopenedNotifier.newDraft.name, 'Banh moi');
    expect(reopenedNotifier.newDraft.priceChips.single.label, 'Nho');
    expect(container.read(provider).category, 'bread');
    expect(container.read(provider).rutTien, isTrue);
    expect(container.read(provider).pickedPhoto?.path, '/tmp/product.jpg');
    expect(
      container.read(contextualProductFormProvider(edit)).pickedPhoto,
      isNull,
    );

    reopenedNotifier.clearNewDraft();
    expect(reopenedNotifier.newDraft.name, isEmpty);
    expect(container.read(provider).pickedPhoto, isNull);
  });

  test('category NEW draft survives edit and clears after create', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(categoryFormProvider.notifier);

    notifier.seed();
    notifier.updateNewDraft(name: 'Do uong', codePrefix: 'DU', slug: 'do_uong');
    notifier.setSelectedIcon('icon-new');
    notifier.seed(editingId: 7, icon: 'icon-edit', active: false);
    notifier.seed();

    expect(notifier.newDraft.name, 'Do uong');
    expect(container.read(categoryFormProvider).selectedIcon, 'icon-new');

    notifier.clearNewDraft();
    expect(notifier.newDraft.name, isEmpty);
  });

  test('blank NEW draft survives edit and clears after create', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(blankFormProvider.notifier);

    notifier.seed(null);
    notifier.updateNewDraft(name: 'Phoi moi', unit: 'kg', notes: 'note');
    notifier.setCategory('bread');
    notifier.seed(const Blank(id: 2, name: 'Edit', category: 'banh_kem'));
    notifier.seed(null);

    expect(notifier.newDraft.name, 'Phoi moi');
    expect(container.read(blankFormProvider).category, 'bread');

    notifier.clearNewDraft();
    expect(notifier.newDraft.name, isEmpty);
  });

  test('template NEW drafts survive edit and stay isolated by system type', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(templateEditorProvider.notifier);

    notifier.seed(null, initialIsSystem: true);
    notifier.updateNewDraft(name: 'Mau moi', body: 'Noi dung');
    notifier.setSelectedScenario('confirm_order');
    notifier.seed(
      const MessageTemplate(
        id: 3,
        scenario: 'ask_info',
        name: 'Edit',
        body: 'Edit body',
        isSystem: false,
      ),
      initialIsSystem: false,
    );
    notifier.seed(null, initialIsSystem: false);

    expect(notifier.newDraft.name, isEmpty);
    expect(container.read(templateEditorProvider).selectedScenario, 'ask_info');
    expect(container.read(templateEditorProvider).isSystem, isFalse);

    notifier.seed(null, initialIsSystem: true);
    expect(notifier.newDraft.name, 'Mau moi');
    expect(
      container.read(templateEditorProvider).selectedScenario,
      'confirm_order',
    );
    expect(container.read(templateEditorProvider).isSystem, isTrue);

    notifier.clearNewDraft();
    expect(notifier.newDraft.name, isEmpty);
  });

  test('knowledge context retains photos without cross-context leakage', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const create = FormDraftContext(
      formType: 'knowledge',
      mode: FormDraftMode.create,
    );
    const edit = FormDraftContext(
      formType: 'knowledge',
      mode: FormDraftMode.edit,
      entityId: '4',
    );
    final provider = contextualKnowledgeFormProvider(create);
    final notifier = container.read(provider.notifier);

    notifier.seed(null);
    notifier.updateNewDraft(title: 'Cong thuc moi', content: 'Noi dung');
    notifier.setSelectedType('recipe');
    notifier.addTag('kem');
    notifier.addPhotos([
      KnowledgeFormPhotoEntry(file: XFile('/tmp/knowledge.jpg')),
    ]);
    container.invalidate(provider);

    final restored = container.read(provider);
    final restoredNotifier = container.read(provider.notifier);
    expect(restoredNotifier.newDraft.title, 'Cong thuc moi');
    expect(restored.selectedType, 'recipe');
    expect(restored.selectedTags, {'kem'});
    expect(restored.photos.single.file?.path, '/tmp/knowledge.jpg');
    expect(
      container.read(contextualKnowledgeFormProvider(edit)).photos,
      isEmpty,
    );

    restoredNotifier.clearNewDraft();
    expect(restoredNotifier.newDraft.title, isEmpty);
  });
}
