import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const createContext = FormDraftContext(
    formType: 'expense',
    mode: FormDraftMode.create,
  );
  const editContext = FormDraftContext(
    formType: 'expense',
    mode: FormDraftMode.edit,
    entityId: '42',
  );

  test('context equality includes form, mode, and every stable identity', () {
    expect(
      const FormDraftContext(
        formType: 'stock-action',
        mode: FormDraftMode.action,
        productId: '7',
        optionId: 'retail',
        variantId: 'price:120000',
      ),
      const FormDraftContext(
        formType: 'stock-action',
        mode: FormDraftMode.action,
        productId: '7',
        optionId: 'retail',
        variantId: 'price:120000',
      ),
    );
    expect(createContext, isNot(editContext));
  });

  test('retainDraft replaces one context without affecting another', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);

    notifier.retainDraft(createContext, 'first');
    notifier.retainDraft(editContext, 42);
    notifier.retainDraft(createContext, 'updated');

    expect(notifier.readDraft<String>(createContext), 'updated');
    expect(notifier.readDraft<int>(editContext), 42);
    expect(container.read(formDraftSessionProvider), hasLength(2));
  });

  test('clearDraft removes only its matching context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);
    notifier.retainDraft(createContext, 'create');
    notifier.retainDraft(editContext, 'edit');

    notifier.clearDraft(createContext);

    expect(notifier.readDraft<String>(createContext), isNull);
    expect(notifier.readDraft<String>(editContext), 'edit');
  });

  test('clearDraftIfUnchanged clears an identical or equal draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);
    const retained = _Draft(1);
    notifier.retainDraft(createContext, retained);

    expect(
      notifier.clearDraftIfUnchanged(createContext, const _Draft(1)),
      isTrue,
    );
    expect(notifier.readDraft<_Draft>(createContext), isNull);

    final identityOnly = _IdentityOnlyDraft();
    notifier.retainDraft(createContext, identityOnly);
    expect(notifier.clearDraftIfUnchanged(createContext, identityOnly), isTrue);
  });

  test('clearDraftIfUnchanged preserves a newer replacement draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);
    const submitted = _Draft(1);
    const replacement = _Draft(2);
    notifier.retainDraft(createContext, submitted);
    notifier.retainDraft(createContext, replacement);

    expect(notifier.clearDraftIfUnchanged(createContext, submitted), isFalse);
    expect(notifier.readDraft<_Draft>(createContext), replacement);
  });

  test('clearAll removes every retained context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);
    notifier.retainDraft(createContext, 'create');
    notifier.retainDraft(editContext, 'edit');

    notifier.clearAll();

    expect(container.read(formDraftSessionProvider), isEmpty);
  });

  test('clearAll advances the epoch even when the registry is empty', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final epochs = <int>[];
    final subscription = container.listen<int>(
      formDraftSessionEpochProvider,
      (previous, next) => epochs.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(formDraftSessionProvider.notifier);

    notifier.clearAll();
    await container.pump();
    notifier.clearAll();
    await container.pump();
    notifier.retainDraft(createContext, 'draft');
    notifier.clearAll();
    await container.pump();

    expect(epochs, <int>[0, 1, 2, 3]);
    expect(container.read(formDraftSessionProvider), isEmpty);
  });

  test('published registry cannot be mutated outside the notifier', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(formDraftSessionProvider.notifier);
    notifier.retainDraft(createContext, 'create');

    expect(
      () => container.read(formDraftSessionProvider)[editContext] = 'edit',
      throwsUnsupportedError,
    );
  });
}

class _Draft {
  const _Draft(this.revision);

  final int revision;

  @override
  bool operator ==(Object other) =>
      other is _Draft && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;
}

class _IdentityOnlyDraft {
  @override
  bool operator ==(Object other) => throw StateError('equality not supported');

  @override
  int get hashCode => identityHashCode(this);
}
