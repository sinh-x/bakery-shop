import '../../../shared/models/form_draft_context.dart';

abstract final class OrderDraftContexts {
  static const createOrder = FormDraftContext(
    formType: 'order',
    mode: FormDraftMode.create,
  );

  static const posCheckout = FormDraftContext(
    formType: 'pos-checkout',
    mode: FormDraftMode.create,
  );

  static const posCheckoutOptions = FormDraftContext(
    formType: 'pos-checkout-options',
    mode: FormDraftMode.create,
  );

  static FormDraftContext addBlank({
    required String orderRef,
    required String workItemId,
    int? assignmentId,
  }) => FormDraftContext(
    formType: 'order-blank',
    mode: assignmentId == null ? FormDraftMode.action : FormDraftMode.edit,
    entityId: orderRef,
    productId: workItemId,
    optionId: assignmentId?.toString(),
  );

  static FormDraftContext recordPayment(String orderRef) => FormDraftContext(
    formType: 'order-payment',
    mode: FormDraftMode.create,
    entityId: orderRef,
  );

  static FormDraftContext editPayment(String orderRef, String transactionId) =>
      FormDraftContext(
        formType: 'order-payment',
        mode: FormDraftMode.edit,
        entityId: orderRef,
        optionId: transactionId,
      );

  static FormDraftContext photoTags(String orderRef, int photoId) =>
      FormDraftContext(
        formType: 'order-photo-tags',
        mode: FormDraftMode.edit,
        entityId: orderRef,
        optionId: photoId.toString(),
      );

  static FormDraftContext transactionPhoto(String orderRef, String txnId) =>
      FormDraftContext(
        formType: 'order-transaction-photo',
        mode: FormDraftMode.action,
        entityId: orderRef,
        optionId: txnId,
      );

  static FormDraftContext editOrder(String orderRef) => FormDraftContext(
    formType: 'order',
    mode: FormDraftMode.edit,
    entityId: orderRef,
  );

  static FormDraftContext workItem(String orderRef, String workItemId) =>
      FormDraftContext(
        formType: 'order-work-item',
        mode: FormDraftMode.edit,
        entityId: orderRef,
        optionId: workItemId,
      );

  static FormDraftContext productPicker(String ownerContext) =>
      FormDraftContext(
        formType: 'order-product-picker',
        mode: FormDraftMode.action,
        entityId: ownerContext,
      );

  static FormDraftContext printChecklist(String orderRef) => FormDraftContext(
    formType: 'order-print-checklist',
    mode: FormDraftMode.action,
    entityId: orderRef,
  );

  static FormDraftContext printWorkItem(String orderRef, int? itemId) =>
      FormDraftContext(
        formType: 'order-print-work-item',
        mode: FormDraftMode.action,
        entityId: orderRef,
        optionId: itemId?.toString() ?? 'all',
      );
}
