import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/order_service.dart';
import '../../../data/api/work_item_service.dart';
import '../../../data/models/order.dart';
import '../../../data/models/order_draft.dart';
import '../../../features/pos/utils/pos_cart_wizard_sync.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/order/order_draft_provider.dart';
import '../../../providers/order/order_list_providers.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/api_error.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/utils/delivery_helpers.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'gated_page_physics.dart';
import 'order_creation_config.dart';
import 'order_stage_indicator.dart';
import 'order_wizard.dart';

/// Shared wizard shell that renders stages 1-4 for both the normal order
/// creation flow and the POS checkout flow.
///
/// The orchestrator is the single source of truth for:
/// - the stage indicator row (reusing [OrderStageIndicator] with `posMode`)
/// - the per-stage widget construction (delegated to [OrderCreationConfig])
/// - forward/back stage navigation (FR8)
/// - the container that hosts the stage widgets (PageView / AnimatedSwitcher,
///   supplied via [StageContainerBuilder]) — FR1
/// - the shared submission pipeline with workflow hooks (Phase 2, FR2/FR3):
///   `onBeforeSubmit` → `createOrder` → photo upload → `orderListProvider`
///   refresh → `onAfterSubmit` → `onNavigateAfterSubmit`.
/// - draft save/restore, gated by [OrderCreationConfig.enableDraft] (FR6).
/// - POS cart sync, gated by [OrderCreationConfig.enableCartSync] (FR7);
///   delegates to the existing `pos_cart_wizard_sync.dart` functions.
///
/// It does NOT own the POS payment step (stage 5 stays in the POS screen) or
/// workflow-specific side effects — those live in the config hooks.
class OrderCreationOrchestrator extends ConsumerStatefulWidget {
  const OrderCreationOrchestrator({
    super.key,
    required this.config,
  });

  final OrderCreationConfig config;

  @override
  ConsumerState<OrderCreationOrchestrator> createState() =>
      _OrderCreationOrchestratorState();
}

class _OrderCreationOrchestratorState
    extends ConsumerState<OrderCreationOrchestrator> {
  OrderCreationConfig get _config => widget.config;

  NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      get _provider => _config.orderStateProvider;

  /// Guards `_submitOrder` against double-tap re-entry (matches the prior
  /// `_submitting` flag in `order_create_screen.dart` and `_isProcessing` in
  /// `pos_checkout_screen.dart`). The host screen reads this via
  /// [OrderCreationController.isSubmitting] to drive its submit button's
  /// `onPressed: null` disabled state.
  bool _isSubmitting = false;

  /// Set to `true` once `onAfterSubmit` + `onNavigateAfterSubmit` complete so
  /// the draft-save helper invoked from `deactivate` does not overwrite a
  /// cleared draft (FR6). Mirrors `_submitted` in `order_create_screen.dart`.
  bool _submitted = false;

  void _goToStage(int stage) {
    final clamped = stage.clamp(1, _config.stageCount);
    ref.read(_provider.notifier).goToStage(clamped);
    _config.onStageChange?.call(clamped);
    // FR6: persist the draft after each stage transition for the normal
    // order workflow. POS has `enableDraft=false` so this is a no-op there.
    if (_config.enableDraft) _saveDraft();
    // FR7: write the wizard Stage-1 working copy back to the POS cart after
    // each stage transition so the cart stays the single source of truth.
    if (_config.enableCartSync) syncWizardItemsToCart(ref);
  }

  void _onSwipe(DragEndDetails d) {
    if (!_config.enableSwipeNavigation) return;
    final s = ref.read(_provider);
    final pv = d.primaryVelocity;
    final target = targetStageForSwipe(
      velocity: Velocity(
        pixelsPerSecond: pv == null ? Offset.zero : Offset(pv, 0),
      ),
      currentStage: s.currentStage,
      pageCount: _config.stageCount,
    );
    if (target != null && s.canNavigateToStage(target)) _goToStage(target);
  }

  OrderCreationController get _controller =>
      OrderCreationController(goToStage: _goToStage);

  List<Widget> _buildStageWidgets() {
    final ctx = context;
    final c = _controller;
    return [
      _config.stage1Builder(ctx, c),
      _config.stage2Builder(ctx, c),
      _config.stage3Builder(ctx, c),
      _config.stage4Builder(ctx, c),
    ];
  }

  // ---------------------------------------------------------------------------
  // FR6 — Draft save/restore (gated by `config.enableDraft`).
  // The helpers are the single source of truth for draft persistence so the
  // host screen (Phase 3 wiring) does not need to duplicate them. POS has
  // `enableDraft=false` so these are no-ops there.
  // ---------------------------------------------------------------------------

  /// Restores the wizard state from `orderDraftProvider` on init. No-op when
  /// `enableDraft` is false or no draft is saved.
  void _restoreDraft() {
    if (!_config.enableDraft) return;
    final draft = ref.read(orderDraftProvider);
    if (draft == null) return;
    final notifier = ref.read(_provider.notifier);
    final data = OrderWizardData(
      customerName: draft.customerName,
      customerPhone: draft.customerPhone,
      deliveryType: draft.deliveryType,
      deliveryAddress: draft.deliveryAddress,
      deliveryPhone: draft.deliveryPhone,
      shippingFee: draft.shippingFee,
      notes: draft.notes,
    );
    notifier.updateWizardData(data);
    notifier.updateItems(List.of(draft.items));
    notifier.updateDueDate(draft.dueDate);
    notifier.updateDueTime(draft.dueTime);
    notifier.updateSource(draft.source);
    notifier.updateSelectedCategorySlug(draft.selectedCategorySlug);
    notifier.updateGpsFields(
      latitude: draft.latitude,
      longitude: draft.longitude,
      googleMapsUrl: draft.googleMapsUrl,
    );
    if (draft.customerId != null) {
      notifier.restoreCustomerFromDraft(draft.customerId!);
    }
    final targetStage = draft.currentStage.clamp(1, _config.stageCount);
    notifier.goToStage(targetStage);
  }

  /// Persists the current wizard state to `orderDraftProvider` unless a
  /// submission has already completed (`_submitted`) — in which case the
  /// draft is cleared instead so a completed order does not re-hydrate.
  void _saveDraft() {
    if (!_config.enableDraft) return;
    if (_submitted) {
      ref.read(orderDraftProvider.notifier).clear();
      return;
    }
    final state = ref.read(_provider);
    final draft = OrderDraft(
      customerName: state.wizardData.customerName,
      customerPhone: state.wizardData.customerPhone,
      deliveryPhone: state.wizardData.deliveryPhone,
      items: List.of(state.items),
      dueDate: state.dueDate,
      dueTime: state.dueTime,
      deliveryType: state.wizardData.deliveryType,
      deliveryAddress: state.wizardData.deliveryAddress,
      shippingFee: state.wizardData.shippingFee,
      notes: state.wizardData.notes,
      source: state.source,
      currentStage: state.currentStage,
      selectedCategorySlug: state.selectedCategorySlug,
      customerId: state.wizardData.selectedCustomer?.id,
      latitude: state.latitude,
      longitude: state.longitude,
      googleMapsUrl: state.googleMapsUrl,
    );
    if (draft.isNotEmpty) {
      ref.read(orderDraftProvider.notifier).save(draft);
    } else {
      ref.read(orderDraftProvider.notifier).clear();
    }
  }

  // ---------------------------------------------------------------------------
  // FR2/FR3 — Shared submission pipeline with workflow hooks (Phase 2).
  // The orchestrator owns the common spine: validate → onBeforeSubmit →
  // createOrder → uploadPendingPhotos → refresh orderListProvider →
  // onAfterSubmit → onNavigateAfterSubmit. Workflow-specific divergent
  // behaviour lives in the config hooks.
  // ---------------------------------------------------------------------------

  /// Shared submission entrypoint invoked by the stage-4 review widget's
  /// submit button (normal order) or the POS payment step's pay-later/pay-now
  /// path. Returns `true` when the order was created and navigation fired.
  ///
  /// The [submitArgs] parameter carries optional workflow-specific createOrder
  /// arguments (POS `status` / `paymentMethod`); normal order passes `null`
  /// and the orchestrator derives the fields from `state`.
  Future<bool> submitOrder({
    String? status,
    String? paymentMethod,
  }) async {
    if (_isSubmitting) return false;
    final state = ref.read(_provider);
    if (state.items.isEmpty) {
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.validationSelectAtLeastOneProduct);
      }
      return false;
    }

    setState(() => _isSubmitting = true);
    try {
      final hookCtx = SubmitHookContext(state: state, ref: ref);
      final prep = await _config.onBeforeSubmit?.call(hookCtx);
      final resolvedCustomerId = prep?.customerId ??
          state.wizardData.selectedCustomer?.id;

      final service = ref.read(orderServiceProvider);
      final customerName = state.wizardData.customerName.isEmpty
          ? OrdersLabels.walkInCustomerFallback
          : state.wizardData.customerName;

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

      final orderItems = _buildOrderItemsPayload(state);

      final order = await service.createOrder(
        customerName: customerName,
        customerPhone: state.wizardData.customerPhone,
        customerId: resolvedCustomerId,
        items: orderItems,
        shippingFee: state.wizardData.shippingFee,
        dueDate: state.dueDate != null ? formatApiDate(state.dueDate!) : null,
        dueTime: state.dueTime != null
            ? formatHourMinute(
                state.dueTime!.hour, state.dueTime!.minute)
            : null,
        deliveryType: state.wizardData.deliveryType,
        deliveryAddress: state.wizardData.deliveryAddress,
        deliveryPhone: state.wizardData.deliveryPhone,
        notes: state.wizardData.notes.trim(),
        source: state.source.isEmpty ? null : state.source,
        status: status,
        paymentMethod: paymentMethod,
        latitude: state.latitude,
        longitude: state.longitude,
        googleMapsUrl: state.googleMapsUrl,
        deliveryTimeSlot: state.dueTime != null
            ? deriveTimeSlot(formatHourMinute(
                state.dueTime!.hour, state.dueTime!.minute))
            : null,
      );

      // Shared per-item photo upload. Workflows can override via
      // `onUploadPendingPhotos` (e.g. POS adds transfer-photo upload).
      if (_config.onUploadPendingPhotos != null) {
        await _config.onUploadPendingPhotos!(ref, order, state);
      } else {
        await _uploadPendingPhotosDefault(order, state);
      }

      // Refresh the order list so the new order appears in the list screen
      // when the user navigates back from the detail/receipt destination.
      await ref.read(orderListProvider.notifier).refresh();

      if (!mounted) return false;

      _submitted = true;
      await _config.onAfterSubmit?.call(hookCtx, order);

      if (!mounted) return false;
      _config.onNavigateAfterSubmit?.call(context, order.orderRef);
      return true;
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Builds the `items` payload for `OrderService.createOrder` from the
  /// current wizard state. Shared by both workflows because the per-item
  /// field mapping is identical (only the workflow-specific extra fields
  /// like POS `attributes.useInventory` differ, and those are already
  /// encoded in `DraftOrderItem.attributes` by the cart-sync layer).
  List<Map<String, dynamic>> _buildOrderItemsPayload(OrderCreateState state) {
    return state.items.map((i) {
      final m = <String, dynamic>{
        'productId': i.product.id.toString(),
        'productName': i.product.name,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'notes': i.notes,
        'isBirthday': i.isBirthday,
        'isExtra': i.isExtra,
        'isGift': i.isGift,
        'attributes': i.attributes,
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
  Future<void> _uploadPendingPhotosDefault(
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
      final workItemId = idx < workItems.length
          ? int.tryParse(workItems[idx].id)
          : null;
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

  @override
  void initState() {
    super.initState();
    // FR6: restore the draft (no-op when `enableDraft=false`).
    _restoreDraft();
    // FR7: seed wizard items from the POS cart on init (no-op when
    // `enableCartSync=false`).
    if (_config.enableCartSync) syncCartToWizardItems(ref);
  }

  @override
  void deactivate() {
    // FR6: persist the draft on exit so a partially-filled normal order
    // survives the user backing out of the wizard. No-op for POS.
    if (_config.enableDraft) _saveDraft();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: OrderStageIndicator(
            currentStage: state.currentStage,
            posMode: _config.posMode,
            onStageTap: (s) {
              if (state.canNavigateToStage(s)) _goToStage(s);
            },
          ),
        ),
        Expanded(
          child: _config.enableSwipeNavigation
              ? GestureDetector(
                  onHorizontalDragEnd: _onSwipe,
                  child: _config.stageContainerBuilder(
                    context,
                    _buildStageWidgets(),
                    state.currentStage,
                  ),
                )
              : _config.stageContainerBuilder(
                  context,
                  _buildStageWidgets(),
                  state.currentStage,
                ),
        ),
      ],
    );
  }
}