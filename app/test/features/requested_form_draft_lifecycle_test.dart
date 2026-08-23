import 'package:bakery_app/features/blanks/providers/blank_stock_action_sheet_notifier.dart';
import 'package:bakery_app/features/blanks/providers/bom_add_sheet_notifier.dart';
import 'package:bakery_app/features/checklist/providers/checklist_config_add_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_record_payment_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_draft_contexts.dart';
import 'package:bakery_app/features/pos/providers/pos_checkout_notifier.dart';
import 'package:bakery_app/features/settings/providers/address_library_editor_notifier.dart';
import 'package:bakery_app/features/settings/providers/catalog_tag_form_notifier.dart';
import 'package:bakery_app/features/stock/providers/reconciliation_sell_waste_modal_notifier.dart';
import 'package:bakery_app/features/stock/providers/stock_action_sheet_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('settings NEW drafts persist until successful clear', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final addressContext = addressLibraryEditorContext(null);
    final address = container.read(
      addressLibraryEditorProvider(addressContext).notifier,
    );
    address.setAddress('12 Nguyen Hue');
    address.setGoogleMapsUrl('https://maps.example/12');
    expect(
      container.read(addressLibraryEditorProvider(addressContext)).address,
      '12 Nguyen Hue',
    );
    address.clear();
    expect(
      container.read(addressLibraryEditorProvider(addressContext)).address,
      isEmpty,
    );

    final tag = container.read(catalogTagFormProvider.notifier);
    tag.setSelectedCategory('dip');
    tag.setKey('sinh-nhat');
    tag.setLabel('Sinh nhat');
    expect(container.read(catalogTagFormProvider).key, 'sinh-nhat');
    tag.clear();
    expect(container.read(catalogTagFormProvider).key, isEmpty);
  });

  test(
    'checklist add drafts are isolated by period and clear independently',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final opening = checklistConfigAddDraftContext('opening');
      final closing = checklistConfigAddDraftContext('closing');

      container
          .read(checklistConfigAddProvider(opening).notifier)
          .setName('Mo cua');
      container
          .read(checklistConfigAddProvider(closing).notifier)
          .setName('Dong cua');

      expect(
        container.read(checklistConfigAddProvider(opening)).name,
        'Mo cua',
      );
      expect(
        container.read(checklistConfigAddProvider(closing)).name,
        'Dong cua',
      );
      container.read(checklistConfigAddProvider(opening).notifier).clear();
      expect(container.read(checklistConfigAddProvider(opening)).name, isEmpty);
      expect(
        container.read(checklistConfigAddProvider(closing)).name,
        'Dong cua',
      );
    },
  );

  test('BOM add drafts are isolated by price chip', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = bomAddDraftContext(10);
    final second = bomAddDraftContext(11);

    container.read(bomAddSheetProvider(first).notifier)
      ..selectBlank(1)
      ..setQuantity('2.5');
    container.read(bomAddSheetProvider(second).notifier)
      ..selectBlank(2)
      ..setQuantity('4');

    expect(container.read(bomAddSheetProvider(first)).selectedBlankId, 1);
    expect(container.read(bomAddSheetProvider(first)).quantity, '2.5');
    expect(container.read(bomAddSheetProvider(second)).selectedBlankId, 2);
    container.read(bomAddSheetProvider(first).notifier).clear();
    expect(container.read(bomAddSheetProvider(first)).selectedBlankId, isNull);
    expect(container.read(bomAddSheetProvider(second)).selectedBlankId, 2);
  });

  test('stock action drafts are isolated by product and action kind', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final restock = stockActionDraftContext(
      productId: 7,
      action: 'restock',
      normalizedPrice: 20000,
    );
    final waste = stockActionDraftContext(
      productId: 7,
      action: 'waste',
      normalizedPrice: 35000,
    );
    final otherProduct = stockActionDraftContext(
      productId: 8,
      action: 'restock',
      normalizedPrice: 20000,
    );

    container.read(stockActionSheetProvider(restock).notifier)
      ..initialize(20000)
      ..setQuantity('3')
      ..setNote('new stock');
    container.read(stockActionSheetProvider(waste).notifier)
      ..initialize(35000)
      ..setQuantity('1')
      ..setReason('damaged');

    expect(container.read(stockActionSheetProvider(restock)).quantity, '3');
    expect(container.read(stockActionSheetProvider(waste)).quantity, '1');
    expect(
      container.read(stockActionSheetProvider(otherProduct)).quantity,
      isEmpty,
    );
    container.read(stockActionSheetProvider(restock).notifier).clear();
    expect(container.read(stockActionSheetProvider(restock)).quantity, isEmpty);
    expect(container.read(stockActionSheetProvider(waste)).quantity, '1');
  });

  test('blank stock drafts are isolated by blank and action kind', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final production = blankStockActionDraftContext(
      blankId: 2,
      action: 'production',
    );
    final usage = blankStockActionDraftContext(blankId: 2, action: 'usage');

    container.read(blankStockActionSheetProvider(production).notifier)
      ..setQuantity('6')
      ..setProducedDate('2026-08-23')
      ..setExpiryDate('2026-08-30');
    container
        .read(blankStockActionSheetProvider(usage).notifier)
        .setQuantity('2');

    expect(
      container.read(blankStockActionSheetProvider(production)).quantity,
      '6',
    );
    expect(container.read(blankStockActionSheetProvider(usage)).quantity, '2');
    container.read(blankStockActionSheetProvider(production).notifier).clear();
    expect(
      container.read(blankStockActionSheetProvider(production)).quantity,
      '1',
    );
    expect(container.read(blankStockActionSheetProvider(usage)).quantity, '2');
  });

  test('reconciliation sale and waste drafts do not leak across options', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saleA = reconciliationActionDraftContext(
      productId: 1,
      optionKey: 'product-a',
      action: 'sale',
    );
    final wasteA = reconciliationActionDraftContext(
      productId: 1,
      optionKey: 'product-a',
      action: 'waste',
    );
    final saleB = reconciliationActionDraftContext(
      productId: 2,
      optionKey: 'product-b',
      action: 'sale',
    );

    container.read(reconciliationSellWasteModalProvider(saleA).notifier)
      ..initializeSale(quantity: '0', unitPrice: '20000', method: 'cash')
      ..setQuantity('3');
    container
        .read(reconciliationSellWasteModalProvider(wasteA).notifier)
        .initializeWaste(quantity: '1', reason: 'broken');

    expect(
      container.read(reconciliationSellWasteModalProvider(saleA)).quantity,
      '3',
    );
    expect(
      container.read(reconciliationSellWasteModalProvider(wasteA)).quantity,
      '1',
    );
    expect(
      container.read(reconciliationSellWasteModalProvider(saleB)).quantity,
      isEmpty,
    );
    container
        .read(reconciliationSellWasteModalProvider(saleA).notifier)
        .clear();
    expect(
      container.read(reconciliationSellWasteModalProvider(wasteA)).quantity,
      '1',
    );
  });

  test(
    'order payment drafts isolate orders, clear submits, and clear photos',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final firstContext = OrderDraftContexts.recordPayment('ORD-1');
      final secondContext = OrderDraftContexts.recordPayment('ORD-2');
      final first = container.read(
        orderRecordPaymentDraftProvider(firstContext).notifier,
      );
      final second = container.read(
        orderRecordPaymentDraftProvider(secondContext).notifier,
      );

      first
        ..setAmount('200')
        ..setNotes('deposit')
        ..setMethod('transfer')
        ..setPendingTransferPhoto(XFile('/tmp/proof.jpg'));
      second.setAmount('500');

      expect(
        container.read(orderRecordPaymentDraftProvider(firstContext)).amount,
        '200',
      );
      expect(
        container.read(orderRecordPaymentDraftProvider(secondContext)).amount,
        '500',
      );
      first.clearPendingTransferPhoto();
      expect(
        container
            .read(orderRecordPaymentDraftProvider(firstContext))
            .pendingTransferPhoto,
        isNull,
      );
      first.clearDraft();
      expect(
        container.read(orderRecordPaymentDraftProvider(firstContext)).amount,
        isEmpty,
      );
      expect(
        container.read(orderRecordPaymentDraftProvider(secondContext)).amount,
        '500',
      );
    },
  );

  test(
    'POS session refresh preserves draft flags and submit clears metadata',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(posCheckoutProvider.notifier);

      notifier
        ..setDeliverImmediately(true)
        ..setStage3ShowFullOptions(true)
        ..markNavigatingAfterCheckout()
        ..startSession(fastPath: false);
      final resumed = container.read(posCheckoutProvider);
      expect(resumed.posDeliverImmediately, isTrue);
      expect(resumed.stage3ShowFullOptions, isTrue);
      expect(resumed.navigatingAfterCheckout, isFalse);

      notifier.clearAfterSubmit();
      final cleared = container.read(posCheckoutProvider);
      expect(cleared.posDeliverImmediately, isFalse);
      expect(cleared.stage3ShowFullOptions, isFalse);
      expect(cleared.navigatingAfterCheckout, isTrue);
    },
  );
}
