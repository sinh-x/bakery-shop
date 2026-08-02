import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order_draft.dart';
import '../../../features/pos/utils/pos_cart_wizard_sync.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/order/order_draft_provider.dart';
import 'gated_page_physics.dart';
import 'order_creation_config.dart';
import 'order_stage_indicator.dart';
import 'order_submission_host.dart';
import 'order_submission_mixin.dart';
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
      OrderCreationOrchestratorState();
}

/// Public state surface so host screens (e.g. POS checkout, DG-322 Phase 4)
/// can drive submission via a [GlobalKey] when the workflow-specific submit
/// button lives outside the orchestrator's stage-4 widget (POS keeps the
/// pay-now/pay-later buttons in its own stage-5 payment step).
///
/// Implements [OrderSubmissionHost] so [OrderSubmissionMixin] depends on the
/// abstract interface rather than this concrete state class. This breaks the
/// prior circular import (orchestrator ↔ mixin) and keeps the submission
/// spine reusable (CQ-2 / CQ-3).
class OrderCreationOrchestratorState
    extends ConsumerState<OrderCreationOrchestrator>
    with OrderSubmissionMixin<OrderCreationOrchestrator>
    implements OrderSubmissionHost {
  // OrderSubmissionHost implementation — exposes the workflow config and the
  // backing provider to the submission mixin without coupling the mixin to
  // this concrete state class.
  @override
  OrderCreationConfig get config => widget.config;

  @override
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState> get provider =>
      config.orderStateProvider;

  void _goToStage(int stage) {
    final clamped = stage.clamp(1, config.stageCount);
    ref.read(provider.notifier).goToStage(clamped);
    config.onStageChange?.call(clamped);
    // FR6: persist the draft after each stage transition for the normal
    // order workflow. POS has `enableDraft=false` so this is a no-op there.
    if (config.enableDraft) _saveDraft();
    // FR7: write the wizard Stage-1 working copy back to the POS cart after
    // each stage transition so the cart stays the single source of truth.
    // Pass the configured provider so POS (posOrderStateProvider) and normal
    // order (orderCreateStateProvider) each sync the correct wizard instance
    // (DG-322 Phase 4).
    if (config.enableCartSync) {
      syncWizardItemsToCart(ref, provider: provider);
    }
  }

  void _onSwipe(DragEndDetails d) {
    if (!config.enableSwipeNavigation) return;
    final s = ref.read(provider);
    final pv = d.primaryVelocity;
    final target = targetStageForSwipe(
      velocity: Velocity(
        pixelsPerSecond: pv == null ? Offset.zero : Offset(pv, 0),
      ),
      currentStage: s.currentStage,
      pageCount: config.stageCount,
    );
    if (target != null && s.canNavigateToStage(target)) _goToStage(target);
  }

  OrderCreationController get _controller => OrderCreationController(
        goToStage: _goToStage,
        submit: submitOrder,
        isSubmitting: isSubmitting,
      );

  List<Widget> _buildStageWidgets() {
    final ctx = context;
    final c = _controller;
    return [
      config.stage1Builder(ctx, c),
      config.stage2Builder(ctx, c),
      config.stage3Builder(ctx, c),
      config.stage4Builder(ctx, c),
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
    if (!config.enableDraft) return;
    final draft = ref.read(orderDraftProvider);
    if (draft == null) return;
    final notifier = ref.read(provider.notifier);
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
    final targetStage = draft.currentStage.clamp(1, config.stageCount);
    notifier.goToStage(targetStage);
  }

  /// Persists the current wizard state to `orderDraftProvider` unless a
  /// submission has already completed (`_submitted`) — in which case this is
  /// a no-op. The post-submit draft clear is owned by the workflow's
  /// `onAfterSubmit` hook (run earlier in the submission spine), so re-clearing
  /// here would modify a provider during `deactivate` (which runs inside a
  /// build phase) and trigger a riverpod build-phase guard. Mirrors the
  /// pre-refactor `order_create_screen._saveDraft` early-return.
  void _saveDraft() {
    if (!config.enableDraft) return;
    if (submitted) return;
    final state = ref.read(provider);
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
  // The common spine (validate → onBeforeSubmit → createOrder → photo upload
  // → refresh orderListProvider → onAfterSubmit → onNavigateAfterSubmit)
  // and the per-item payload builder / default photo-upload loop live in
  // [OrderSubmissionMixin] so this file stays under the 400-line threshold
  // (DG-322 / CQ-1). `submitOrder` remains public on this state class via the
  // mixin, so host screens can still call it through a
  // `GlobalKey<OrderCreationOrchestratorState>`.
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // FR6: restore the draft (no-op when `enableDraft=false`). Done in
    // initState because the draft restore must land before the first build
    // so the initial stage reflects the persisted state.
    _restoreDraft();
    // FR7: seed wizard items from the POS cart on init (no-op when
    // `enableCartSync=false`). Deferred to a post-frame callback because the
    // orchestrator is constructed inside its host screen's build, and
    // modifying `posOrderStateProvider` synchronously during initState would
    // trip riverpod's "modify provider while widget tree is building" guard
    // (the host screen watches `posCartProvider`, which the sync reads).
    if (config.enableCartSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) syncCartToWizardItems(ref, provider: provider);
      });
    }
  }

  @override
  void deactivate() {
    // FR6: persist the draft on exit so a partially-filled normal order
    // survives the user backing out of the wizard. No-op for POS.
    if (config.enableDraft) _saveDraft();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(provider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: OrderStageIndicator(
            currentStage: state.currentStage,
            posMode: config.posMode,
            onStageTap: (s) {
              if (state.canNavigateToStage(s)) _goToStage(s);
            },
          ),
        ),
        Expanded(
          child: config.enableSwipeNavigation
              ? GestureDetector(
                  onHorizontalDragEnd: _onSwipe,
                  child: config.stageContainerBuilder(
                    context,
                    _buildStageWidgets(),
                    state.currentStage,
                  ),
                )
              : config.stageContainerBuilder(
                  context,
                  _buildStageWidgets(),
                  state.currentStage,
                ),
        ),
      ],
    );
  }
}