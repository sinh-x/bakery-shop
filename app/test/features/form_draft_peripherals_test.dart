import 'package:bakery_app/data/models/catalog_photo.dart';
import 'package:bakery_app/features/auth/providers/login_form_notifier.dart';
import 'package:bakery_app/features/auth/providers/password_change_notifier.dart';
import 'package:bakery_app/features/cash_drawer/providers/cash_drawer_selector_notifier.dart';
import 'package:bakery_app/features/products/providers/catalog_photo_viewer_notifier.dart';
import 'package:bakery_app/features/products/providers/catalog_tag_edit_notifier.dart';
import 'package:bakery_app/features/settings/providers/address_library_editor_notifier.dart';
import 'package:bakery_app/features/settings/providers/catalog_tag_form_notifier.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/providers/printer_picker_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'address drafts isolate create and edit and clear on session boundary',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final create = addressLibraryEditorContext(null);
      final edit = addressLibraryEditorContext(42);

      container.read(addressLibraryEditorProvider(create).notifier)
        ..setAddress('Create address')
        ..setAddressError('create error');
      container.read(addressLibraryEditorProvider(edit).notifier)
        ..setAddress('Edit address')
        ..setSaving(true);

      expect(
        container.read(addressLibraryEditorProvider(create)).address,
        'Create address',
      );
      expect(
        container.read(addressLibraryEditorProvider(edit)).address,
        'Edit address',
      );
      expect(
        container.read(addressLibraryEditorProvider(create)).saving,
        isFalse,
      );

      container.read(formDraftSessionProvider.notifier).clearAll();
      expect(
        container.read(addressLibraryEditorProvider(create)).address,
        isEmpty,
      );
      expect(
        container.read(addressLibraryEditorProvider(edit)).address,
        isEmpty,
      );
    },
  );

  test('catalog-tag nullable category clears and logout removes the draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(catalogTagFormProvider.notifier);

    notifier
      ..setSelectedCategory('occasion')
      ..setKey('birthday');
    notifier.setSelectedCategory(null);

    expect(container.read(catalogTagFormProvider).selectedCategory, isNull);
    expect(container.read(catalogTagFormProvider).key, 'birthday');
    container.read(formDraftSessionProvider.notifier).clearAll();
    expect(container.read(catalogTagFormProvider).key, isEmpty);
  });

  test('cash-drawer selections and fields remain action-context isolated', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cashIn = cashDrawerActionContext('drawer-7', 'cash-in');
    final cashOut = cashDrawerActionContext('drawer-7', 'cash-out');

    container.read(cashDrawerSelectorProvider(cashIn).notifier)
      ..setSelectedValue('employee')
      ..setSelectedStaffName('Lan')
      ..setAmount('100000')
      ..setNote('Tien le');
    container
        .read(cashDrawerSelectorProvider(cashOut).notifier)
        .setAmount('50000');

    expect(
      container.read(cashDrawerSelectorProvider(cashIn)).selectedStaffName,
      'Lan',
    );
    expect(container.read(cashDrawerSelectorProvider(cashIn)).note, 'Tien le');
    expect(container.read(cashDrawerSelectorProvider(cashOut)).amount, '50000');
    expect(
      container.read(cashDrawerSelectorProvider(cashOut)).selectedValue,
      'owner',
    );

    container.read(cashDrawerSelectorProvider(cashIn).notifier).clear();
    expect(container.read(cashDrawerSelectorProvider(cashIn)).amount, isEmpty);
    expect(container.read(cashDrawerSelectorProvider(cashOut)).amount, '50000');
  });

  test(
    'catalog photo tag drafts isolate photo identity and clear explicitly',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const firstPhoto = CatalogPhoto(
        id: 1,
        productId: 8,
        filePath: '/one.jpg',
        caption: 'First',
        tags: 'birthday',
      );
      const secondPhoto = CatalogPhoto(
        id: 2,
        productId: 8,
        filePath: '/two.jpg',
        caption: 'Second',
      );
      final first = catalogTagEditContext(8, 1);
      final second = catalogTagEditContext(8, 2);

      container.read(catalogTagEditProvider(first).notifier)
        ..seed(firstPhoto)
        ..setCaption('First draft')
        ..toggleTag('style');
      container.read(catalogTagEditProvider(second).notifier).seed(secondPhoto);

      expect(
        container.read(catalogTagEditProvider(first)).caption,
        'First draft',
      );
      expect(
        container.read(catalogTagEditProvider(first)).selectedTags,
        containsAll(<String>['birthday', 'style']),
      );
      expect(container.read(catalogTagEditProvider(second)).caption, 'Second');
      expect(
        container.read(catalogTagEditProvider(second)).selectedTags,
        isEmpty,
      );

      container.read(catalogTagEditProvider(first).notifier).clear();
      expect(container.read(catalogTagEditProvider(first)).caption, isEmpty);
      expect(container.read(catalogTagEditProvider(second)).caption, 'Second');
    },
  );

  test('viewer and printer operation state cannot leak across contexts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final viewerA = catalogPhotoViewerContext(1);
    final viewerB = catalogPhotoViewerContext(2);
    final printA = PrinterPickerDialogContext();
    final printB = PrinterPickerDialogContext();
    final printASubscription = container.listen(
      printerPickerProvider(printA),
      (_, _) {},
    );
    final printBSubscription = container.listen(
      printerPickerProvider(printB),
      (_, _) {},
    );
    addTearDown(printASubscription.close);
    addTearDown(printBSubscription.close);

    container.read(catalogPhotoViewerProvider(viewerA).notifier)
      ..setCurrentIndex(3)
      ..setDownloading(true);
    container
        .read(printerPickerProvider(printA).notifier)
        .setError('printer A');

    expect(container.read(catalogPhotoViewerProvider(viewerB)).currentIndex, 0);
    expect(
      container.read(catalogPhotoViewerProvider(viewerB)).downloading,
      isFalse,
    );
    expect(container.read(printerPickerProvider(printB)).errorMessage, isNull);
    expect(
      container.read(printerPickerProvider(printA)).errorMessage,
      'printer A',
    );
  });

  test('logout epoch resets live operation state with an empty registry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final address = addressLibraryEditorContext(null);
    final cash = cashDrawerActionContext('drawer-9', 'cash-in');
    final viewer = catalogPhotoViewerContext(9);
    final printer = PrinterPickerDialogContext();
    final printerSubscription = container.listen(
      printerPickerProvider(printer),
      (_, _) {},
    );
    addTearDown(printerSubscription.close);

    container
        .read(addressLibraryEditorProvider(address).notifier)
        .setAddressError('address error');
    container.read(cashDrawerSelectorProvider(cash).notifier).rebuild();
    container.read(catalogTagFormOperationProvider.notifier).setSaving(true);
    container
        .read(catalogPhotoViewerProvider(viewer).notifier)
        .setDownloading(true);
    container
        .read(printerPickerProvider(printer).notifier)
        .setError('printer error');
    container.read(loginFormProvider.notifier)
      ..startSubmitting()
      ..setErrorMessage('login error');
    container.read(passwordChangeFormProvider.notifier)
      ..startSubmitting()
      ..setErrorMessage('password error');
    expect(container.read(formDraftSessionProvider), isEmpty);

    container.read(formDraftSessionProvider.notifier).clearAll();

    expect(
      container.read(addressLibraryEditorProvider(address)).addressError,
      isNull,
    );
    expect(container.read(cashDrawerSelectorProvider(cash)).rebuildCounter, 0);
    expect(container.read(catalogTagFormOperationProvider), isFalse);
    expect(
      container.read(catalogPhotoViewerProvider(viewer)).downloading,
      isFalse,
    );
    expect(container.read(printerPickerProvider(printer)).errorMessage, isNull);
    expect(container.read(loginFormProvider).submitting, isFalse);
    expect(container.read(loginFormProvider).errorMessage, isNull);
    expect(container.read(passwordChangeFormProvider).submitting, isFalse);
    expect(container.read(passwordChangeFormProvider).errorMessage, isNull);
  });

  test(
    'printer operation family disposes after its dialog listener closes',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final context = PrinterPickerDialogContext();
      final provider = printerPickerProvider(context);
      final subscription = container.listen(provider, (_, _) {});

      container.read(provider.notifier).setError('temporary');
      expect(container.read(provider).errorMessage, 'temporary');
      subscription.close();
      await container.pump();

      expect(container.exists(provider), isFalse);
      expect(container.read(provider).errorMessage, isNull);
    },
  );

  test('compare-clear preserves a newer replacement address draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final context = addressLibraryEditorContext(null);
    final notifier = container.read(
      addressLibraryEditorProvider(context).notifier,
    );

    notifier.setAddress('submitted');
    final submitted =
        container.read(formDraftSessionProvider)[context]
            as AddressLibraryEditorState;
    notifier.setAddress('newer replacement');

    expect(
      container
          .read(formDraftSessionProvider.notifier)
          .clearDraftIfUnchanged(context, submitted),
      isFalse,
    );
    expect(
      container.read(addressLibraryEditorProvider(context)).address,
      'newer replacement',
    );
  });

  test('auth reset removes stale non-sensitive operation state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(loginFormProvider.notifier)
      ..startSubmitting()
      ..setErrorMessage('login error')
      ..reset();
    container.read(passwordChangeFormProvider.notifier)
      ..startSubmitting()
      ..setErrorMessage('password error')
      ..reset();

    expect(container.read(loginFormProvider).submitting, isFalse);
    expect(container.read(loginFormProvider).errorMessage, isNull);
    expect(container.read(passwordChangeFormProvider).submitting, isFalse);
    expect(container.read(passwordChangeFormProvider).errorMessage, isNull);
  });
}
