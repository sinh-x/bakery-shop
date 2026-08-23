import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/events/providers/event_form_notifier.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('event edit retains photos without cross-entity leakage', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const context = FormDraftContext(
      formType: 'event',
      mode: FormDraftMode.edit,
      entityId: '9',
    );
    const other = FormDraftContext(
      formType: 'event',
      mode: FormDraftMode.edit,
      entityId: '10',
    );
    final provider = contextualEventFormProvider(context);
    final notifier = container.read(provider.notifier);

    notifier
      ..startEdit(
        BakeryEvent(
          id: 9,
          timestamp: DateTime(2026, 8, 20),
          type: 'equipment',
          summary: 'Edit summary',
          tags: const ['maintenance'],
        ),
      )
      ..setSummary('Unfinished note')
      ..setCustomTagInput('unfinished-tag')
      ..setSelectedType('production')
      ..toggleTag('staff', selected: true)
      ..setSelectedPhotos([XFile('/tmp/new-event.jpg')]);

    container.invalidate(provider);
    final reopened = container.read(provider);
    expect(reopened.editingId, 9);
    expect(reopened.newDraft.summary, 'Unfinished note');
    expect(reopened.newDraft.customTagInput, 'unfinished-tag');
    expect(reopened.selectedType, 'production');
    expect(reopened.selectedTags, contains('staff'));
    expect(reopened.selectedPhotos.single.path, '/tmp/new-event.jpg');
    expect(
      container.read(contextualEventFormProvider(other)).selectedPhotos,
      isEmpty,
    );
  });

  test('successful NEW event reset restores clean defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(eventFormProvider.notifier);

    notifier
      ..setSummary('Submitted')
      ..setSelectedType('delivery')
      ..toggleTag('ordering', selected: true)
      ..clearNewDraft();

    final cleared = container.read(eventFormProvider);
    expect(cleared.editingId, isNull);
    expect(cleared.newDraft.summary, isEmpty);
    expect(cleared.newDraft.customTagInput, isEmpty);
    expect(cleared.selectedType, 'note');
    expect(cleared.selectedTags, isEmpty);
    expect(cleared.selectedPhotos, isEmpty);
  });

  test('standalone and order-linked NEW drafts stay isolated', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(eventFormProvider.notifier);

    notifier
      ..startNew('standalone')
      ..setSummary('General note')
      ..startNew('order:42')
      ..setSummary('Order incident');

    notifier.startNew('standalone');
    expect(container.read(eventFormProvider).newDraft.summary, 'General note');

    notifier.startNew('order:42');
    expect(
      container.read(eventFormProvider).newDraft.summary,
      'Order incident',
    );

    notifier.startNew('order:43');
    expect(container.read(eventFormProvider).newDraft.summary, isEmpty);
  });
}
