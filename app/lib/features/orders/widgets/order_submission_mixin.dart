import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/order_service.dart';
import '../../../data/api/work_item_service.dart';
import '../../../data/models/order.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../data/providers/order/order_list_providers.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/services/session_cache.dart';
import '../../../shared/utils/api_error.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/utils/delivery_helpers.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'order_creation_config.dart';
import 'order_submission_host.dart';

/// Submission pipeline extracted from the orchestrator state so the
/// orchestrator file stays under the 400-line threshold (DG-322 / CQ-1).
///
/// Owns the shared submission spine:
/// `onBeforeSubmit` → `createOrder` → photo upload → `orderListProvider`
/// refresh → `onAfterSubmit` → `onNavigateAfterSubmit`, plus the per-item
/// payload builder and the default photo-upload loop. The re-entry guard
/// (`isSubmitting`) and the post-submit latch (`submitted`) live here so the
/// host's draft-save helper can read `submitted` via the public getter.
///
/// Constrained to `ConsumerState<W>` (generic over the host widget type) so
/// the mixin can be applied to any `ConsumerState` subclass without importing
/// the concrete orchestrator. The workflow config and backing provider are
/// exposed via the abstract [config] and [provider] getters, which match the
/// [OrderSubmissionHost] interface the host implements. This breaks the
/// prior circular import (orchestrator ↔ mixin) and lets the submission
/// spine be reused by any host that implements [OrderSubmissionHost]
/// (CQ-2 / CQ-3). Host screens still call `submitOrder` via a `GlobalKey`
/// typed against the concrete state class — see
/// `OrderCreationOrchestratorState`.
mixin OrderSubmissionMixin<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  /// The workflow configuration. Provided by the host state class (which
  /// implements [OrderSubmissionHost]); `widget` is only visible on the host.
  OrderCreationConfig get config;

  /// The provider backing the wizard state. Provided by the host state class
  /// for the same reason as [config].
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      get provider;
  /// Guards `submitOrder` against double-tap re-entry (matches the prior
  /// `_submitting` flag in `order_create_screen.dart` and `_isProcessing` in
  /// `pos_checkout_screen.dart`). The host screen reads this via
  /// [OrderCreationController.isSubmitting] to drive its submit button's
  /// `onPressed: null` disabled state.
  bool _isSubmitting = false;

  /// Set to `true` once `onAfterSubmit` + `onNavigateAfterSubmit` complete so
  /// the draft-save helper invoked from `deactivate` does not overwrite a
  /// cleared draft (FR6). Mirrors `_submitted` in `order_create_screen.dart`.
  bool _submitted = false;

  /// Whether the shared submission spine is currently in progress. Read by
  /// the orchestrator's `_controller` getter to populate
  /// [OrderCreationController.isSubmitting].
  bool get isSubmitting => _isSubmitting;

  /// Post-submit latch read by the host's `_saveDraft` helper so it
  /// skips persisting a draft after a successful submission (FR6).
  bool get submitted => _submitted;

  /// Shared submission entrypoint invoked by the stage-4 review widget's
  /// submit button (normal order) or the POS payment step's pay-later/pay-now
  /// path. Returns `true` when the order was created and navigation fired.
  ///
  /// The [status] / [paymentMethod] parameters carry optional
  /// workflow-specific createOrder arguments (POS); normal order passes
  /// `null` and the orchestrator derives the fields from `state`.
  Future<bool> submitOrder({
    String? status,
    String? paymentMethod,
  }) async {
    if (_isSubmitting) return false;
    final state = ref.read(provider);
    if (state.items.isEmpty) {
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.validationSelectAtLeastOneProduct);
      }
      return false;
    }

    setState(() => _isSubmitting = true);
    try {
      final hookCtx = SubmitHookContext(state: state, ref: ref, context: context);
      final prep = await _validateAndPrepare(state, hookCtx);
      final order = await _createOrder(
        state: state,
        prep: prep,
        hookCtx: hookCtx,
        status: status,
        paymentMethod: paymentMethod,
      );
      return await _handlePostSubmit(state, order, hookCtx);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Stage 1 — pre-submit validation and preparation: runs `onBeforeSubmit`
  /// and resolves the customer id. Returns the prep result to feed
  /// [_createOrder]. Extracted from `submitOrder` to keep the spine under
  /// the 60-line threshold (DG-322 / CQ-6).
  Future<SubmitPreparation?> _validateAndPrepare(
    OrderCreateState state,
    SubmitHookContext hookCtx,
  ) async {
    final prep = await config.onBeforeSubmit?.call(hookCtx);
    return prep;
  }

  /// Stage 2 — order creation: resolves `createdBy`, enforces the price
  /// floor (FR3/AC3), builds the items payload, and calls `createOrder`.
  /// Returns the freshly created [Order]. Extracted from `submitOrder`
  /// (DG-322 / CQ-6).
  Future<Order> _createOrder({
    required OrderCreateState state,
    required SubmitPreparation? prep,
    required SubmitHookContext hookCtx,
    required String? status,
    required String? paymentMethod,
  }) async {
    final resolvedCustomerId =
        prep?.customerId ?? state.wizardData.selectedCustomer?.id;

    final service = ref.read(orderServiceProvider);
    final customerName = state.wizardData.customerName.isEmpty
        ? OrdersLabels.walkInCustomerFallback
        : state.wizardData.customerName;
    // `createdBy` is workflow-supplied (normal order resolves it from
    // `loggedByProvider`; POS leaves it empty to match pre-refactor
    // behaviour). Resolved here so the shared spine stays the single
    // `createOrder` call site.
    final createdBy = config.createdByResolver?.call(ref) ?? '';

    // Price floor enforcement (FR3/AC3): clamp selling price to the
    // assigned price for trưng bày markup items before submitting.
    // DG-296 Phase 4 — kept on the shared path so both workflows apply it.
    for (final i in state.items) {
      if (i.product.isTrungBay &&
          i.assignedPrice != null &&
          i.unitPrice < i.assignedPrice!) {
        i.customUnitPrice = i.assignedPrice;
      }
    }

    final orderItems = buildOrderItemsPayload(state);

    return service.createOrder(
      customerName: customerName,
      customerPhone: state.wizardData.customerPhone,
      customerId: resolvedCustomerId,
      items: orderItems,
      shippingFee: state.wizardData.shippingFee,
      dueDate: state.dueDate != null ? formatApiDate(state.dueDate!) : null,
      dueTime: state.dueTime != null
          ? formatHourMinute(state.dueTime!.hour, state.dueTime!.minute)
          : null,
      deliveryType: state.wizardData.deliveryType,
      deliveryAddress: state.wizardData.deliveryAddress,
      deliveryPhone: state.wizardData.deliveryPhone,
      notes: state.wizardData.notes.trim(),
      source: state.source.isEmpty ? null : state.source,
      status: status,
      paymentMethod: paymentMethod,
      createdBy: createdBy,
      latitude: state.latitude,
      longitude: state.longitude,
      googleMapsUrl: state.googleMapsUrl,
      deliveryTimeSlot: state.dueTime != null
          ? deriveTimeSlot(
              formatHourMinute(state.dueTime!.hour, state.dueTime!.minute))
          : null,
    );
  }

  /// Stage 3 — post-submit: photo upload, order-list refresh, `onAfterSubmit`
  /// hook, and `onNavigateAfterSubmit`. Sets the `_submitted` latch and
  /// returns `true` when navigation fired. Extracted from `submitOrder`
  /// (DG-322 / CQ-6).
  Future<bool> _handlePostSubmit(
    OrderCreateState state,
    Order order,
    SubmitHookContext hookCtx,
  ) async {
    // Shared per-item photo upload. Workflows can override via
    // `onUploadPendingPhotos` (e.g. POS adds transfer-photo upload).
    if (config.onUploadPendingPhotos != null) {
      await config.onUploadPendingPhotos!(ref, order, state);
    } else {
      await uploadPendingPhotosDefault(order, state);
    }

    // Refresh the order list so the new order appears in the list screen
    // when the user navigates back from the detail/receipt destination.
    // Gated by `enableOrderListRefresh` (POS skips it — the user navigates
    // to the receipt, not the order list, and the pre-refactor POS flow
    // did not refresh the list). DG-322 Phase 4.
    if (config.enableOrderListRefresh) {
      await ref.read(orderListProvider.notifier).refresh();
    }
    // DG-409 Phase 5 (FR13, AC6): a new order is a mutation on the order
    // entity type, so invalidate the session-level order-history cache so
    // the next history-tab visit re-fetches fresh data.
    ref
        .read(sessionCacheProvider)
        .invalidateEntityType(SessionCacheEntity.orderHistory);

    if (!mounted) return false;

    _submitted = true;
    await config.onAfterSubmit?.call(hookCtx, order);

    if (!mounted) return false;
    config.onNavigateAfterSubmit?.call(context, order.orderRef);
    return true;
  }

  /// Builds the `items` payload for `OrderService.createOrder` from the
  /// current wizard state. Shared by both workflows because the per-item
  /// field mapping is identical (only the workflow-specific extra fields
  /// like POS `attributes.useInventory` differ, and those are already
  /// encoded in `DraftOrderItem.attributes` by the cart-sync layer).
  List<Map<String, dynamic>> buildOrderItemsPayload(OrderCreateState state) {
    return state.items.map((i) {
      // Bridge `DraftOrderItem.candleType` into `attributes['candle_type']`
      // for API persistence (DG-340 Phase 4 / FR2, NFR2). Only include a real
      // candle type — null/empty/`khong_nen` map to "no candle" and are omitted
      // so the attributes map stays clean (AC7). Follows the existing
      // `is_birthday`/`age` pattern of conditionally attaching fields.
      final attrs = Map<String, dynamic>.from(i.attributes);
      final candle = i.candleType;
      if (candle != null && candle.isNotEmpty && candle != 'khong_nen') {
        attrs['candle_type'] = candle;
      } else {
        attrs.remove('candle_type');
      }
      final m = <String, dynamic>{
        'productId': i.product.id.toString(),
        'productName': i.product.name,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'notes': i.notes,
        'isBirthday': i.isBirthday,
        'isExtra': i.isExtra,
        'isGift': i.isGift,
        'attributes': attrs,
        'priceChipId': i.priceChipId,
        if (i.assignedPrice != null) 'assignedPrice': i.assignedPrice,
      };
      if (i.isBirthday && i.age.isNotEmpty) {
        final age = int.tryParse(i.age.trim());
        if (age != null) m['age'] = age;
      }
      return m;
    }).toList();
  }

  /// Default per-item photo upload used when `onUploadPendingPhotos` is not
  /// supplied. Mirrors the loop in `order_create_screen.dart` so the normal
  /// order workflow keeps its existing photo-upload behavior (with the
  /// failed-photo summary snackbar) after extraction.
  Future<void> uploadPendingPhotosDefault(
    Order order,
    OrderCreateState state,
  ) async {
    final hasPerItemPhotos = state.items.any(
      (i) => i.pendingPhotos.isNotEmpty,
    );
    if (!hasPerItemPhotos) return;
    final service = ref.read(orderServiceProvider);
    final workItemSvc = ref.read(workItemServiceProvider);
    final workItems = await workItemSvc.listWorkItems(order.orderRef);
    workItems.sort((a, b) => a.position.compareTo(b.position));

    int totalPhotos = 0;
    int failedPhotos = 0;
    for (var idx = 0; idx < state.items.length; idx++) {
      final draftItem = state.items[idx];
      if (draftItem.pendingPhotos.isEmpty) continue;
      final workItemId =
          idx < workItems.length ? int.tryParse(workItems[idx].id) : null;
      for (final xfile in draftItem.pendingPhotos) {
        totalPhotos++;
        try {
          await service.uploadOrderPhoto(
            order.orderRef,
            xfile,
            workItemId: workItemId,
          );
        } catch (e) {
          failedPhotos++;
          debugPrint('Photo upload failed (${xfile.path}): $e');
        }
      }
    }
    if (failedPhotos > 0 && mounted) {
      showTopSnackBar(
        context,
        OrdersLabels.photoUploadResult(
          totalPhotos - failedPhotos,
          totalPhotos,
          failedPhotos,
        ),
      );
    }
  }
}