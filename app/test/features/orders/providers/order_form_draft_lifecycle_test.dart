import 'package:bakery_app/features/orders/providers/order_draft_contexts.dart';
import 'package:bakery_app/features/orders/providers/order_edit_payment_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_edit_wizard_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_form_operation_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_photo_tag_edit_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_record_payment_notifier.dart';
import 'package:bakery_app/features/orders/providers/order_submission_guard_notifier.dart';
import 'package:bakery_app/features/orders/providers/product_picker_notifier.dart';
import 'package:bakery_app/features/orders/providers/work_item_edit_card_notifier.dart';
import 'package:bakery_app/features/pos/providers/pos_checkout_notifier.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('record-payment contexts retain values and photos without leaking', () {
    final contextA = OrderDraftContexts.recordPayment('ORD-A');
    final contextB = OrderDraftContexts.recordPayment('ORD-B');
    final providerA = orderRecordPaymentDraftProvider(contextA);
    final providerB = orderRecordPaymentDraftProvider(contextB);
    final photo = XFile('/tmp/transfer-a.jpg');

    container.read(providerA.notifier)
      ..setAmount('250')
      ..setNotes('A only')
      ..setMethod('transfer')
      ..setPaymentSource('VCB')
      ..setPendingTransferPhoto(photo);

    expect(container.read(providerA).amount, '250');
    expect(container.read(providerA).pendingTransferPhoto, same(photo));
    expect(container.read(providerB).amount, isEmpty);
    expect(container.read(providerB).pendingTransferPhoto, isNull);
    expect(container.read(formDraftSessionProvider), contains(contextA));
    expect(container.read(formDraftSessionProvider), isNot(contains(contextB)));

    container.invalidate(providerA);
    expect(container.read(providerA).notes, 'A only');
    expect(container.read(providerA).pendingTransferPhoto, same(photo));

    container.read(providerA.notifier).clearDraft();
    expect(container.read(formDraftSessionProvider), isNot(contains(contextA)));
    expect(container.read(providerA).pendingTransferPhoto, isNull);
  });

  test('edit-payment nullable clear and reused provider key are stable', () {
    final context = OrderDraftContexts.editPayment('ORD-A', 'TXN-1');
    final provider = orderEditPaymentProvider(context);
    container
        .read(provider.notifier)
        .seed(
          type: 'payment',
          method: 'transfer',
          paymentSource: 'Old account',
          createdAt: DateTime(2026, 8, 23, 10),
          amount: '100',
          notes: 'retry me',
        );

    container.read(provider.notifier).setPaymentSource(null);
    expect(container.read(provider).paymentSource, isNull);
    expect(container.read(formDraftSessionProvider), contains(context));

    container.invalidate(provider);
    expect(container.read(provider).paymentSource, isNull);
    expect(container.read(provider).notes, 'retry me');
  });

  test('photo-tag and product-picker drafts are entity/owner isolated', () {
    final photoA = OrderDraftContexts.photoTags('ORD-A', 1);
    final photoB = OrderDraftContexts.photoTags('ORD-A', 2);
    final pickerA = OrderDraftContexts.productPicker('order-edit:ORD-A');
    final pickerB = OrderDraftContexts.productPicker('order-edit:ORD-B');

    container.read(orderPhotoTagEditProvider(photoA).notifier)
      ..seedTags({'chat-zalo'})
      ..toggleTag('chuyen-khoan', true);
    container.read(orderPhotoTagEditProvider(photoB).notifier).seedTags({
      'mau-trang-tri',
    });
    container.read(productPickerProvider(pickerA).notifier).seedInitial({
      11,
      12,
    });
    container.read(productPickerProvider(pickerB).notifier).seedInitial({21});

    expect(container.read(orderPhotoTagEditProvider(photoA)).selectedTags, {
      'chat-zalo',
      'chuyen-khoan',
    });
    expect(container.read(orderPhotoTagEditProvider(photoB)).selectedTags, {
      'mau-trang-tri',
    });
    expect(container.read(productPickerProvider(pickerA)).selectedIds, {
      11,
      12,
    });
    expect(container.read(productPickerProvider(pickerB)).selectedIds, {21});
  });

  test('work-item reused IDs remain isolated by order identity', () {
    final contextA = OrderDraftContexts.workItem('ORD-A', '7');
    final contextB = OrderDraftContexts.workItem('ORD-B', '7');

    container.read(workItemEditCardProvider(contextA).notifier)
      ..setNotes('Order A')
      ..setCashAmount('500000');
    container.read(workItemEditCardProvider(contextB).notifier)
      ..setNotes('Order B')
      ..setCashAmount('200000');

    expect(container.read(workItemEditCardProvider(contextA)).notes, 'Order A');
    expect(
      container.read(workItemEditCardProvider(contextA)).cashAmount,
      '500000',
    );
    expect(container.read(workItemEditCardProvider(contextB)).notes, 'Order B');
  });

  test('work-item success clears retention without resetting live UI', () {
    final context = OrderDraftContexts.workItem('ORD-A', '7');
    final provider = workItemEditCardProvider(context);

    container.read(provider.notifier).setNotes('Saved note');
    container.read(provider.notifier).markSaved();

    expect(container.read(formDraftSessionProvider), isNot(contains(context)));
    expect(container.read(provider).notes, 'Saved note');
  });

  test('operation failure/finish and submission guards are context scoped', () {
    final operationA = OrderDraftContexts.transactionPhoto('ORD-A', 'TXN-1');
    final operationB = OrderDraftContexts.transactionPhoto('ORD-B', 'TXN-1');

    container.read(orderFormOperationProvider(operationA).notifier).start();
    expect(container.read(orderFormOperationProvider(operationA)).busy, isTrue);
    expect(
      container.read(orderFormOperationProvider(operationB)).busy,
      isFalse,
    );

    container
        .read(orderFormOperationProvider(operationA).notifier)
        .fail(StateError('request failed'));
    expect(
      container.read(orderFormOperationProvider(operationA)).busy,
      isFalse,
    );
    expect(
      container.read(orderFormOperationProvider(operationA)).error,
      isNotNull,
    );

    // Mirrors a request completing after its widget was dismissed.
    container.read(orderFormOperationProvider(operationA).notifier).finish();
    expect(
      container.read(orderFormOperationProvider(operationA)).error,
      isNull,
    );

    container
        .read(
          orderSubmissionGuardProvider(OrderDraftContexts.createOrder).notifier,
        )
        .setSubmitting(true);
    expect(
      container.read(
        orderSubmissionGuardProvider(OrderDraftContexts.posCheckout),
      ),
      isFalse,
    );
  });

  test('order edit nullable clears survive retained draft restore', () {
    final context = OrderDraftContexts.editOrder('ORD-A');
    final provider = orderEditWizardProvider(context);
    final notifier = container.read(provider.notifier);

    notifier
      ..setDueTime(const TimeOfDay(hour: 8, minute: 0))
      ..setDueTime(null)
      ..setAssignedStaffId('12')
      ..setAssignedStaffId(null)
      ..setAddressSelected('https://maps.example/a')
      ..setAddressSelected(null);

    expect(container.read(provider).dueTime, isNull);
    expect(container.read(provider).assignedStaffId, isNull);
    expect(container.read(provider).existingGoogleMapsUrl, isNull);
    container.invalidate(provider);
    expect(container.read(provider).dueTime, isNull);
    expect(container.read(provider).assignedStaffId, isNull);
  });

  test('POS option success clears only POS option draft', () {
    final paymentContext = OrderDraftContexts.recordPayment('ORD-A');
    container
        .read(orderRecordPaymentDraftProvider(paymentContext).notifier)
        .setAmount('90');
    container.read(posCheckoutProvider.notifier)
      ..setDeliverImmediately(true)
      ..setStage3ShowFullOptions(true);

    expect(
      container.read(formDraftSessionProvider),
      contains(OrderDraftContexts.posCheckoutOptions),
    );
    container.read(posCheckoutProvider.notifier).clearAfterSubmit();

    expect(
      container.read(formDraftSessionProvider),
      isNot(contains(OrderDraftContexts.posCheckoutOptions)),
    );
    expect(container.read(formDraftSessionProvider), contains(paymentContext));
  });

  test('session clear resets already-live retained providers', () {
    final paymentContext = OrderDraftContexts.recordPayment('ORD-A');
    final workItemContext = OrderDraftContexts.workItem('ORD-A', '7');
    final paymentProvider = orderRecordPaymentDraftProvider(paymentContext);
    final workItemProvider = workItemEditCardProvider(workItemContext);

    container.read(paymentProvider.notifier).setAmount('250000');
    container.read(workItemProvider.notifier).setNotes('Do not leak');
    expect(container.read(paymentProvider).amount, '250000');
    expect(container.read(workItemProvider).notes, 'Do not leak');

    container.read(formDraftSessionProvider.notifier).clearAll();

    expect(container.read(paymentProvider).amount, isEmpty);
    expect(container.read(paymentProvider).method, 'cash');
    expect(container.read(workItemProvider).notes, isEmpty);
  });

  test('logout epoch removes the entire previous-user POS checkout', () {
    const product = Product(
      id: 1,
      name: 'Banh mi',
      basePrice: 20000,
      category: 'bread',
      active: 1,
    );
    container.read(posCartProvider.notifier).addItem(product);
    container.read(posOrderStateProvider.notifier)
      ..updateSource('walk-in')
      ..goToStage(4);
    container.read(posCheckoutProvider.notifier)
      ..setDeliverImmediately(true)
      ..setStage3ShowFullOptions(true);
    container
        .read(
          orderSubmissionGuardProvider(OrderDraftContexts.posCheckout).notifier,
        )
        .setSubmitting(true);

    container.read(formDraftSessionProvider.notifier).clearAll();

    expect(container.read(posCartProvider).items, isEmpty);
    expect(container.read(posOrderStateProvider).items, isEmpty);
    expect(container.read(posOrderStateProvider).source, isEmpty);
    expect(container.read(posOrderStateProvider).currentStage, 1);
    expect(container.read(posCheckoutProvider).posDeliverImmediately, isFalse);
    expect(container.read(posCheckoutProvider).stage3ShowFullOptions, isFalse);
    expect(
      container.read(
        orderSubmissionGuardProvider(OrderDraftContexts.posCheckout),
      ),
      isFalse,
    );
  });

  test('older completion cannot clear a newer same-key draft', () {
    final context = OrderDraftContexts.recordPayment('ORD-A');
    final provider = orderRecordPaymentDraftProvider(context);
    container.read(provider.notifier).setNotes('old submission');
    final oldDraft = container.read(formDraftSessionProvider)[context]!;

    container.read(provider.notifier).setNotes('newly reopened draft');
    final cleared = container
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context, oldDraft);

    expect(cleared, isFalse);
    expect(container.read(provider).notes, 'newly reopened draft');
    expect(container.read(formDraftSessionProvider), contains(context));
  });

  test('dismissed and stale operations settle without touching newer work', () {
    final context = OrderDraftContexts.recordPayment('ORD-A');
    final provider = orderFormOperationProvider(context);
    final notifier = container.read(provider.notifier);
    final dismissedGeneration = notifier.start();

    notifier.failIfCurrent(dismissedGeneration, StateError('failed after pop'));
    expect(container.read(provider).error, isNotNull);
    notifier.finishIfCurrent(dismissedGeneration);
    expect(container.read(provider).busy, isFalse);
    expect(container.read(provider).error, isNull);

    final oldGeneration = notifier.start();
    final newGeneration = notifier.start();
    notifier.failIfCurrent(oldGeneration, StateError('stale'));
    notifier.finishIfCurrent(oldGeneration);
    expect(container.read(provider).busy, isTrue);
    expect(container.read(provider).error, isNull);

    notifier.finishIfCurrent(newGeneration);
    expect(container.read(provider).busy, isFalse);
  });
}
