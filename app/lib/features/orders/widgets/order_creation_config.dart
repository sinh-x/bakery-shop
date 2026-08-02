import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../providers/order/order_create_state_provider.dart';

/// Builds the container that hosts the wizard stage widgets.
///
/// Each workflow provides its own implementation:
/// - Normal order → `PageView` driven by a `PageController` synced to
///   `currentStage`.
/// - POS → `AnimatedSwitcher` keyed on `currentStage`.
///
/// The orchestrator owns the 4 stage widgets and the current stage number;
/// the container decides how to present/animate them.
typedef StageContainerBuilder = Widget Function(
  BuildContext context,
  List<Widget> stageWidgets,
  int currentStage,
);

/// Builds a single wizard stage widget. The [controller] exposes the
/// orchestrator's stage-navigation primitive so the stage's
/// `onContinue`/`onBack` callbacks can delegate back to the orchestrator
/// without knowing which provider instance or container is in use.
typedef StageBuilder = Widget Function(
  BuildContext context,
  OrderCreationController controller,
);

/// Surface handed to each stage builder so stages can drive wizard navigation
/// without coupling to the host screen.
class OrderCreationController {
  /// Moves the wizard to the 1-based [stage] (1..4). The orchestrator updates
  /// the configured [OrderCreateStateNotifier] and notifies the container.
  final void Function(int stage) goToStage;

  /// Submits the wizard via the orchestrator's shared submission spine. The
  /// stage-4 review widget's submit button invokes this so the host screen
  /// does not need to reach into the orchestrator's state. Returns `true`
  /// when the order was created and navigation fired.
  final Future<bool> Function() submit;

  /// Whether the shared submission spine is currently in progress. Stage 4
  /// reads this to disable its submit button and show the spinner while the
  /// orchestrator's `submitOrder` runs (mirrors the pre-refactor `_submitting`
  /// flag on `order_create_screen.dart` and `_isProcessing` on POS).
  final bool isSubmitting;

  const OrderCreationController({
    required this.goToStage,
    required this.submit,
    this.isSubmitting = false,
  });
}

/// Context handed to workflow-specific submission hooks so they can run
/// pre/post-submission logic without the orchestrator needing to know which
/// workflow is active. The hook receives the current [OrderCreateState] and
/// the [WidgetRef] of the orchestrator so it can read/write providers.
class SubmitHookContext {
  final OrderCreateState state;
  final WidgetRef ref;
  final BuildContext context;

  const SubmitHookContext({
    required this.state,
    required this.ref,
    required this.context,
  });
}

/// Result of [OrderCreationConfig.onBeforeSubmit]. Workflow-specific hooks
/// return pre-submission mutations that the orchestrator applies before
/// calling `OrderService.createOrder`.
///
/// Currently the only mutable field is [customerId] — workflows may resolve
/// a customer id (e.g. normal order auto-creates a customer) before the
/// orchestrator sends the create request. Other fields stay on `state`.
class SubmitPreparation {
  /// Customer id to send to `createOrder`. When non-null, overrides the
  /// `state.wizardData.selectedCustomer?.id` value the orchestrator would
  /// otherwise use. Null means "use whatever the state already has".
  final int? customerId;

  const SubmitPreparation({this.customerId});
}

/// Hook invoked before `OrderService.createOrder` runs. Workflows use it to
/// perform pre-submission side effects:
/// - Normal order: auto-create a customer when name+phone are present and no
///   `selectedCustomer` is set.
/// - POS: no-op (POS does not auto-create customers).
///
/// The hook may be async (e.g. calling `customerService.createCustomer`).
/// Returning `null` is equivalent to `SubmitPreparation()`.
typedef OnBeforeSubmitHook = Future<SubmitPreparation?> Function(
  SubmitHookContext ctx,
);

/// Hook invoked after `OrderService.createOrder` succeeds and the orchestrator
/// has finished shared post-submission work (photo upload, order-list
/// refresh). Workflows use it for divergent cleanup:
/// - Normal order: clear `orderDraftProvider`, reset `orderCreateStateProvider`.
/// - POS: clear `posCartProvider`, invalidate `productsProvider` /
///   `stockOverviewProvider`, run any cart-write-back already performed.
///
/// The hook receives the created [Order] so it can derive the `orderRef` if
/// needed (e.g. for payment transactions).
typedef OnAfterSubmitHook = Future<void> Function(
  SubmitHookContext ctx,
  Order order,
);

/// Hook invoked after `onAfterSubmit` completes successfully. Workflows use it
/// to navigate to the workflow-specific destination via `pushReplacement`:
/// - Normal order: `context.pushReplacement('/orders/{orderRef}')`.
/// - POS: `context.pushReplacement('/pos/receipt/{orderRef}')`.
///
/// The orchestrator passes the current [BuildContext] so the hook can use
/// `go_router` without the orchestrator importing it.
typedef OnNavigateAfterSubmitHook = void Function(
  BuildContext context,
  String orderRef,
);

/// Workflow-specific configuration consumed by [OrderCreationOrchestrator].
///
/// This model is the single change point for behaviour that differs between
/// the normal order creation flow and the POS checkout flow while sharing the
/// 4-stage wizard shell. Phase 1 covers stage rendering (FR1, FR8); submission
/// hooks are added in Phase 2.
@immutable
class OrderCreationConfig {
  /// Provider instance backing this wizard — `orderCreateStateProvider` for
  /// normal orders, `posOrderStateProvider` for POS.
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      orderStateProvider;

  /// Whether the stage indicator renders the 5-stage POS variant. Only the
  /// first 4 stages are rendered by the orchestrator; stage 5 stays in the
  /// POS screen wrapper.
  final bool posMode;

  /// Gates draft save/restore. `true` for normal order, `false` for POS
  /// (FR6). Used by the orchestrator's draft save/restore helpers so the
  /// POS workflow never persists a draft.
  final bool enableDraft;

  /// Gates POS cart sync (PosCartItem ↔ DraftOrderItem). `true` for POS,
  /// `false` for normal order (FR7). When enabled, the orchestrator calls
  /// the existing `pos_cart_wizard_sync` functions at the correct lifecycle
  /// points (seed items on init, write-back on stage-1 continue / app-bar
  /// back). Normal order leaves this false because it never touches the POS
  /// cart.
  final bool enableCartSync;

  /// Enables horizontal-swipe stage navigation (normal order only). POS uses
  /// explicit back/continue buttons, so swipe is disabled there.
  final bool enableSwipeNavigation;

  /// Number of wizard stages rendered by the orchestrator. Both workflows
  /// currently render 4 stages; kept configurable for future extensibility.
  final int stageCount;

  /// Per-stage widget builders. Each workflow supplies its own builders so
  /// POS can substitute `PosReviewPanel` for stage 4 and the pickup variant
  /// for stage 3 while reusing the shared shell.
  final StageBuilder stage1Builder;
  final StageBuilder stage2Builder;
  final StageBuilder stage3Builder;
  final StageBuilder stage4Builder;

  /// Container builder that wraps the stage widgets (PageView / AnimatedSwitcher).
  final StageContainerBuilder stageContainerBuilder;

  /// Optional hook invoked after the orchestrator advances to a new stage.
  /// Used by workflows that need to react to stage changes (e.g. resetting
  /// POS pickup flags when entering stage 3).
  final void Function(int stage)? onStageChange;

  /// Resolves the `createdBy` value sent to `OrderService.createOrder`.
  ///
  /// The shared submission spine does not know who the current staff member
  /// is — that is a workflow/environment concern. Normal order resolves it
  /// from `loggedByProvider`; POS does not set `createdBy` (matches the
  /// pre-refactor POS behaviour). Returning an empty string omits the field
  /// (see `OrderService.createOrder`).
  final String Function(WidgetRef ref)? createdByResolver;

  /// Workflow-specific pre-submission hook (Phase 2, FR2/FR3/FR6/FR7).
  ///
  /// The orchestrator awaits this before calling `OrderService.createOrder`.
  /// Normal order uses it to auto-create a customer; POS uses it to transfer
  /// `tien_rut` photos / no-op. See [OnBeforeSubmitHook].
  final OnBeforeSubmitHook? onBeforeSubmit;

  /// Workflow-specific post-submission hook (Phase 2). The orchestrator
  /// awaits this after uploading per-item photos and refreshing
  /// `orderListProvider`. Normal order uses it to clear `orderDraftProvider`
  /// and reset `orderCreateStateProvider`; POS uses it to clear
  /// `posCartProvider` and invalidate `productsProvider` /
  /// `stockOverviewProvider`. See [OnAfterSubmitHook].
  final OnAfterSubmitHook? onAfterSubmit;

  /// Workflow-specific navigation hook (Phase 2, FR2/FR3). The orchestrator
  /// invokes this after `onAfterSubmit` succeeds. Normal order does
  /// `context.pushReplacement('/orders/{orderRef}')`; POS does
  /// `context.pushReplacement('/pos/receipt/{orderRef}')`. See
  /// [OnNavigateAfterSubmitHook].
  final OnNavigateAfterSubmitHook? onNavigateAfterSubmit;

  /// Optional builder for the per-item photo-upload step that runs after
  /// `createOrder` succeeds. Both workflows currently upload per-item
  /// `pendingPhotos` via `orderService.uploadOrderPhoto`; the builder is
  /// extracted so each workflow can supply its own upload routine without
  /// the orchestrator duplicating the loop. Returning `null` skips photo
  /// upload entirely (used by POS when `skipPayment` is true).
  ///
  /// The hook receives the created [Order] and the orchestrator's [WidgetRef].
  final Future<void> Function(WidgetRef ref, Order order, OrderCreateState state)? onUploadPendingPhotos;

  const OrderCreationConfig({
    required this.orderStateProvider,
    required this.posMode,
    required this.enableDraft,
    required this.enableCartSync,
    required this.enableSwipeNavigation,
    required this.stage1Builder,
    required this.stage2Builder,
    required this.stage3Builder,
    required this.stage4Builder,
    required this.stageContainerBuilder,
    this.stageCount = 4,
    this.onStageChange,
    this.createdByResolver,
    this.onBeforeSubmit,
    this.onAfterSubmit,
    this.onNavigateAfterSubmit,
    this.onUploadPendingPhotos,
  });
}