import 'package:bakery_app/features/blanks/providers/blank_stock_action_sheet_notifier.dart';
import 'package:bakery_app/features/blanks/providers/bom_add_sheet_notifier.dart';
import 'package:bakery_app/features/checklist/providers/checklist_config_add_notifier.dart';
import 'package:bakery_app/features/stock/providers/reconciliation_sell_waste_modal_notifier.dart';
import 'package:bakery_app/features/stock/providers/stock_action_sheet_notifier.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nhap kho isolates product and normalized-price drafts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chipA = stockActionDraftContext(
      productId: 7,
      action: 'restock',
      normalizedPrice: 20000,
    );
    final chipB = stockActionDraftContext(
      productId: 7,
      action: 'restock',
      normalizedPrice: 35000,
    );
    final productB = stockActionDraftContext(
      productId: 8,
      action: 'restock',
      normalizedPrice: 20000,
    );

    container.read(stockActionSheetProvider(chipA).notifier)
      ..initialize(20000)
      ..setQuantity('4')
      ..setNote('chip A');

    expect(container.read(stockActionSheetProvider(chipB)).quantity, isEmpty);
    expect(
      container.read(stockActionSheetProvider(productB)).isLoading,
      isFalse,
    );
    expect(container.read(formDraftSessionProvider), contains(chipA));
    expect(container.read(formDraftSessionProvider), isNot(contains(chipB)));

    container.invalidate(stockActionSheetProvider(chipA));
    final reopened = container.read(stockActionSheetProvider(chipA));
    expect(reopened.quantity, '4');
    expect(reopened.note, 'chip A');
    expect(reopened.selectedNormalizedPrice, 20000);
  });

  test('stock defaults and explicit normalized-price null are preserved', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final context = stockActionDraftContext(
      productId: 3,
      action: 'restock',
      normalizedPrice: 18000,
    );
    final notifier = container.read(stockActionSheetProvider(context).notifier);

    notifier.initialize(18000);
    expect(container.read(formDraftSessionProvider), isEmpty);
    notifier.setSelectedNormalizedPrice(null);

    expect(
      container.read(stockActionSheetProvider(context)).selectedNormalizedPrice,
      isNull,
    );
    expect(container.read(formDraftSessionProvider), contains(context));
    container.invalidate(stockActionSheetProvider(context));
    expect(
      container.read(stockActionSheetProvider(context)).selectedNormalizedPrice,
      isNull,
    );
  });

  test('dismissed stock request stays contextual and settles cleanly', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = stockActionDraftContext(
      productId: 1,
      action: 'restock',
      normalizedPrice: 10000,
    );
    final second = stockActionDraftContext(
      productId: 2,
      action: 'restock',
      normalizedPrice: 10000,
    );
    final notifier = container.read(stockActionSheetProvider(first).notifier)
      ..initialize(10000)
      ..setQuantity('2')
      ..setLoading(true);

    expect(container.read(stockActionSheetProvider(first)).isLoading, isTrue);
    expect(container.read(stockActionSheetProvider(second)).isLoading, isFalse);

    notifier.setLoading(false);
    container.invalidate(stockActionSheetProvider(first));
    final reopened = container.read(stockActionSheetProvider(first));
    expect(reopened.quantity, '2');
    expect(reopened.isLoading, isFalse);
  });

  test(
    'reconciliation payment method supports explicit null and clean reopen',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final context = reconciliationActionDraftContext(
        productId: 1,
        optionKey: '1:20000',
        action: 'sale',
      );
      final notifier = container.read(
        reconciliationSellWasteModalProvider(context).notifier,
      );

      notifier.initializeSale(
        quantity: '0',
        unitPrice: '20000',
        method: 'cash',
      );
      notifier.setPaymentMethod(null);
      notifier.setPaymentMethodError(true);
      expect(
        container
            .read(reconciliationSellWasteModalProvider(context))
            .paymentMethod,
        isNull,
      );

      container.invalidate(reconciliationSellWasteModalProvider(context));
      final reopened = container.read(
        reconciliationSellWasteModalProvider(context),
      );
      expect(reopened.paymentMethod, isNull);
      expect(reopened.paymentMethodError, isFalse);
    },
  );

  test('BOM selection clears to null without affecting another chip', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = bomAddDraftContext(10);
    final second = bomAddDraftContext(11);

    container.read(bomAddSheetProvider(first).notifier).selectBlank(4);
    container.read(bomAddSheetProvider(second).notifier).selectBlank(5);
    container.read(bomAddSheetProvider(first).notifier).selectBlank(null);

    expect(container.read(bomAddSheetProvider(first)).selectedBlankId, isNull);
    expect(container.read(bomAddSheetProvider(second)).selectedBlankId, 5);
  });

  test('blank actions and checklist periods reopen independently', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final production = blankStockActionDraftContext(
      blankId: 9,
      action: 'production',
    );
    final usage = blankStockActionDraftContext(blankId: 9, action: 'usage');
    final opening = checklistConfigAddDraftContext('opening');
    final closing = checklistConfigAddDraftContext('closing');

    container
        .read(blankStockActionSheetProvider(production).notifier)
        .setQuantity('6');
    container
        .read(blankStockActionSheetProvider(usage).notifier)
        .setQuantity('2');
    container
        .read(checklistConfigAddProvider(opening).notifier)
        .setName('Mo cua');

    container.invalidate(blankStockActionSheetProvider(production));
    container.invalidate(checklistConfigAddProvider(opening));
    expect(
      container.read(blankStockActionSheetProvider(production)).quantity,
      '6',
    );
    expect(container.read(blankStockActionSheetProvider(usage)).quantity, '2');
    expect(container.read(checklistConfigAddProvider(opening)).name, 'Mo cua');
    expect(container.read(checklistConfigAddProvider(closing)).name, isEmpty);
  });

  test('session clear resets mounted operational draft families', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final stock = stockActionDraftContext(
      productId: 4,
      action: 'restock',
      normalizedPrice: 25000,
    );
    final checklist = checklistConfigAddDraftContext('opening');

    container.read(stockActionSheetProvider(stock).notifier)
      ..initialize(25000)
      ..setQuantity('3');
    container
        .read(checklistConfigAddProvider(checklist).notifier)
        .setName('Kiem tra cua');

    container.read(formDraftSessionProvider.notifier).clearAll();

    expect(container.read(stockActionSheetProvider(stock)).quantity, isEmpty);
    expect(container.read(checklistConfigAddProvider(checklist)).name, isEmpty);
  });

  test(
    'session epoch resets transient operational state with empty registry',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final stockContext = stockActionDraftContext(
        productId: 31,
        action: 'restock',
        normalizedPrice: null,
      );
      final reconciliationContext = reconciliationActionDraftContext(
        productId: 32,
        optionKey: '32:40000',
        action: 'sell',
      );
      final blankContext = blankStockActionDraftContext(
        blankId: 33,
        action: 'production',
      );
      final bomContext = bomAddDraftContext(34);
      final checklistContext = checklistConfigAddDraftContext('weekly');

      container
          .read(stockActionSheetProvider(stockContext).notifier)
          .setLoading(true);
      final reconciliationNotifier = container.read(
        reconciliationSellWasteModalProvider(reconciliationContext).notifier,
      );
      reconciliationNotifier.setPaymentMethodError(true);
      reconciliationNotifier.rebuild();
      container
          .read(blankStockActionSheetProvider(blankContext).notifier)
          .setSaving(true);
      container.read(bomAddSheetProvider(bomContext).notifier).setSaving(true);
      container.read(checklistConfigAddProvider(checklistContext));

      expect(container.read(formDraftSessionProvider), isEmpty);
      container.read(formDraftSessionProvider.notifier).clearAll();

      expect(
        container.read(stockActionSheetProvider(stockContext)).isLoading,
        isFalse,
      );
      final reconciliation = container.read(
        reconciliationSellWasteModalProvider(reconciliationContext),
      );
      expect(reconciliation.paymentMethodError, isFalse);
      expect(reconciliation.rebuildToken, 0);
      expect(
        container.read(blankStockActionSheetProvider(blankContext)).saving,
        isFalse,
      );
      expect(container.read(bomAddSheetProvider(bomContext)).saving, isFalse);
      expect(
        container.read(checklistConfigAddProvider(checklistContext)).name,
        isEmpty,
      );
    },
  );

  test(
    'stale async completions preserve newer blank BOM and checklist drafts',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final blankContext = blankStockActionDraftContext(
        blankId: 41,
        action: 'usage',
      );
      final bomContext = bomAddDraftContext(42);
      final checklistContext = checklistConfigAddDraftContext('weekly');

      final blankNotifier = container.read(
        blankStockActionSheetProvider(blankContext).notifier,
      );
      blankNotifier.setQuantity('2');
      final submittedBlank = blankNotifier.retainedDraft;
      blankNotifier.setQuantity('3');
      blankNotifier.setSaving(true);
      expect(blankNotifier.completeSuccess(submittedBlank), isFalse);
      expect(
        container.read(blankStockActionSheetProvider(blankContext)).quantity,
        '3',
      );
      expect(
        container.read(blankStockActionSheetProvider(blankContext)).saving,
        isFalse,
      );

      final bomNotifier = container.read(
        bomAddSheetProvider(bomContext).notifier,
      );
      bomNotifier.selectBlank(7);
      final submittedBom = bomNotifier.retainedDraft;
      bomNotifier.selectBlank(8);
      bomNotifier.setSaving(true);
      expect(bomNotifier.completeSuccess(submittedBom), isFalse);
      expect(
        container.read(bomAddSheetProvider(bomContext)).selectedBlankId,
        8,
      );
      expect(container.read(bomAddSheetProvider(bomContext)).saving, isFalse);

      final checklistNotifier = container.read(
        checklistConfigAddProvider(checklistContext).notifier,
      );
      checklistNotifier.setName('Ban dau');
      final submittedChecklist = checklistNotifier.retainedDraft;
      checklistNotifier.setName('Moi hon');
      expect(checklistNotifier.completeSuccess(submittedChecklist), isFalse);
      expect(
        container.read(checklistConfigAddProvider(checklistContext)).name,
        'Moi hon',
      );

      expect(
        blankNotifier.completeSuccess(blankNotifier.retainedDraft),
        isTrue,
      );
      expect(bomNotifier.completeSuccess(bomNotifier.retainedDraft), isTrue);
      expect(
        checklistNotifier.completeSuccess(checklistNotifier.retainedDraft),
        isTrue,
      );
      expect(
        container.read(blankStockActionSheetProvider(blankContext)).quantity,
        '1',
      );
      expect(
        container.read(bomAddSheetProvider(bomContext)).selectedBlankId,
        isNull,
      );
      expect(
        container.read(checklistConfigAddProvider(checklistContext)).name,
        isEmpty,
      );
    },
  );
}
