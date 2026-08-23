// DG-322 Phase 4: thin wrapper over OrderCreationOrchestrator for stages
// 1-4. Stage 5 (POS payment step) stays in this file — it is POS-specific
// (cash/transfer, editable amount, tien_rut, target account). The
// orchestrator owns the shared stage shell, indicator, and submission
// spine; this screen supplies the POS OrderCreationConfig and delegates
// stage-5 payment state/handlers to PosCheckoutPaymentController (NFR4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/orders/widgets/order_creation_config.dart';
import '../../features/orders/widgets/order_creation_orchestrator.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/widgets/stage1_product_selection_screen.dart';
import '../../features/orders/widgets/stage2_customer_info_screen.dart';
import '../../features/orders/widgets/stage3_delivery_options_screen.dart';
import '../../features/orders/providers/order_submission_guard_notifier.dart';
import '../../features/orders/providers/order_draft_contexts.dart';
import '../../features/pos/widgets/pos_checkout_payment_controller.dart';
import '../../features/pos/widgets/pos_payment_step_builder.dart';
import '../../features/pos/widgets/pos_review_panel.dart';
import '../../features/pos/widgets/pos_stage3_pickup_screen.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/pos_provider.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import '../pos/utils/pos_cart_wizard_sync.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'providers/pos_checkout_notifier.dart';

String posCheckoutLocalDueDate(DateTime dateTime) {
  return formatApiDate(dateTime);
}

@visibleForTesting
String resolvePosCheckoutErrorMessage(Object error) {
  return api_error.normalizeApiError(error).message;
}

@visibleForTesting
String? extractBackendDetail(Object? data) {
  return api_error.extractBackendDetail(data);
}

class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key, this.fastPath = false});

  /// When `true`, the screen initializes with Giao ngay walk-in defaults and
  /// jumps directly to Stage 5 (Thanh toán). "Quay lại" from Stage 5 returns
  /// to the POS product grid instead of Stage 4 (DG-370 Phase 1, FR1/FR3).
  final bool fastPath;

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  // DG-404 Phase 4.5: local mutable flag migrated to `posCheckoutProvider`
  // (`posDeliverImmediately`, `stage3ShowFullOptions`, `isFastPath`,
  // `navigatingAfterCheckout`). The `_posStateInitialized` guard stays
  // local because it only prevents re-entry into `_initPosState` within a
  // single widget instance (no observable UI state, no setState).
  bool _posStateInitialized = false;

  late final PosCheckoutPaymentController _payment;
  final GlobalKey<OrderCreationOrchestratorState> _orchestratorKey =
      GlobalKey<OrderCreationOrchestratorState>();

  @override
  void initState() {
    super.initState();
    ref.listenManual<OrderCreateState>(posOrderStateProvider, (_, next) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(OrderDraftContexts.posCheckout, next);
    });
    _payment = PosCheckoutPaymentController(
      submitOrder: ({status, paymentMethod}) =>
          _orchestratorKey.currentState?.submitOrder(
            status: status,
            paymentMethod: paymentMethod,
          ) ??
          Future.value(false),
      resolveDeliveryType: () =>
          ref.read(posOrderStateProvider).wizardData.deliveryType,
      goToStage: _goToStage,
      writeBackToCart: _writeBackToCart,
      // DG-370 Phase 1 — fast-path "Quay lại" returns to the POS product
      // grid (/pos) instead of Stage 4 (FR3/AC5).
      backFromPaymentStepOverride: widget.fastPath
          ? _backFromPaymentStepFastPath
          : null,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // DG-404 review CQ-1: reset the post-submit latch so each new POS
      // checkout starts with `submitted=false`. The latch is a global
      // non-autoDispose `NotifierProvider` shared with the normal order
      // flow; without a reset here, the FR6 draft-save guard (no-op for
      // POS since `enableDraft=false`, but the latch also gates the
      // shared submission spine's post-submit hook chain) would stay
      // latched from the prior order.
      ref
          .read(
            orderSubmissionLatchProvider(
              OrderDraftContexts.posCheckout,
            ).notifier,
          )
          .resetSubmitted();
      _initPosState();
    });
  }

  void _initPosState() {
    if (_posStateInitialized) return;
    _posStateInitialized = true;

    final checkoutNotifier = ref.read(posCheckoutProvider.notifier);
    checkoutNotifier.startSession(fastPath: widget.fastPath);
    // DG-404 review CQ-2: reset the navigating-after-checkout latch so this
    // fresh checkout session re-enables the empty-cart guard. The latch is
    // a global non-autoDispose `NotifierProvider` that would otherwise stay
    // `true` from the previous checkout and prevent the guard from
    // redirecting to `/pos` on an empty cart.
    final posNotifier = ref.read(posOrderStateProvider.notifier);
    final retained = ref
        .read(formDraftSessionProvider.notifier)
        .readDraft<OrderCreateState>(OrderDraftContexts.posCheckout);
    if (retained != null) {
      posNotifier.updateItems(retained.items);
      posNotifier.updateWizardData(retained.wizardData);
      posNotifier.updateDueDate(retained.dueDate);
      posNotifier.updateDueTime(retained.dueTime);
      posNotifier.updateSource(retained.source);
      posNotifier.updateSelectedCategorySlug(retained.selectedCategorySlug);
      posNotifier.updateGpsFields(
        latitude: retained.latitude,
        clearLatitude: retained.latitude == null,
        longitude: retained.longitude,
        clearLongitude: retained.longitude == null,
        googleMapsUrl: retained.googleMapsUrl,
        clearGoogleMapsUrl: retained.googleMapsUrl == null,
      );
      posNotifier.goToStage(retained.currentStage);
    }
    final current = ref.read(posOrderStateProvider);
    final isFreshCheckout =
        current.source.isEmpty &&
        current.wizardData.customerName.isEmpty &&
        current.wizardData.notes.isEmpty &&
        current.wizardData.deliveryAddress.isEmpty;
    if (isFreshCheckout) {
      const wizardData = OrderWizardData(
        customerName: OrdersLabels.khachLe,
        source: OrdersLabels.taiTiemPOS,
        deliveryType: 'pickup',
      );
      posNotifier.updateWizardData(wizardData);
      posNotifier.updateSource(OrdersLabels.taiTiemPOS);
      final posDue = posDefaultDueDateTime(DateTime.now());
      posNotifier.updateDueDate(
        DateTime(posDue.year, posDue.month, posDue.day),
      );
      posNotifier.updateDueTime(
        TimeOfDay(hour: posDue.hour, minute: posDue.minute),
      );
      posNotifier.goToStage(1);
    }

    if (widget.fastPath) {
      // DG-370 Phase 1/3 — Giao ngay fast-path: jump directly to Stage 5 with
      // deliverImmediately=true so the order is created with status
      // "delivered" (same semantics as PosStage3PickupScreen "Giao ngay").
      // Phase 3: persist the flag on the payment controller so BOTH pay-now
      // and pay-later produce status="delivered" (FR4).
      checkoutNotifier.setDeliverImmediately(true);
      _payment.deliverImmediately = true;
      // Seed the wizard items from the POS cart so the payment step has the
      // cart contents available (mirrors the orchestrator's init safety net,
      // but run synchronously here because the fast-path skips Stages 1-4).
      syncCartToWizardItems(ref, provider: posOrderStateProvider);
      _enterPaymentStep();
    }
  }

  void _goToStage(int stage) {
    if (stage == 3) {
      ref.read(posCheckoutProvider.notifier).resetStage3();
    }
    ref.read(posOrderStateProvider.notifier).goToStage(stage);
  }

  void _writeBackToCart() {
    final state = ref.read(posOrderStateProvider);
    if (state.items.isEmpty) return;
    final cartItems = state.items.map(draftItemToCart).toList();
    ref.read(posCartProvider.notifier).replaceCart(cartItems);
  }

  void _enterPaymentStep() {
    _payment.enterPaymentStep(ref);
  }

  /// DG-370 Phase 5.6-c1 (UX-1..UX-6): "Giao ngay & Thanh toán" fast-path
  /// invoked from any POS checkout stage (1-4). Sets deliverImmediately=true
  /// (so the order is created with status="delivered" on both pay-now and
  /// pay-later, FR4) and jumps to Stage 5. Used as the `onFastPath` callback
  /// for Stage 1/2/3/4 bottom navigation buttons.
  void _enterFastPath() {
    ref.read(posCheckoutProvider.notifier).setDeliverImmediately(true);
    _payment.deliverImmediately = true;
    _enterPaymentStep();
  }

  /// DG-370 Phase 1 — fast-path "Quay lại": write the wizard items back to
  /// the cart (so the cart survives the back-out) and return to the POS
  /// product grid (/pos) instead of Stage 4 (FR3/AC5).
  void _backFromPaymentStepFastPath() {
    _writeBackToCart();
    if (mounted) context.go('/pos');
  }

  void _discardCheckout() {
    ref.read(posCartProvider.notifier).clearCart();
    ref.read(posOrderStateProvider.notifier).reset();
    ref
        .read(formDraftSessionProvider.notifier)
        .clearDraft(OrderDraftContexts.posCheckout);
    ref.read(posCheckoutProvider.notifier).clearAfterSubmit();
  }

  OrderCreationConfig _buildConfig() {
    final checkoutState = ref.read(posCheckoutProvider);
    return OrderCreationConfig(
      orderStateProvider: posOrderStateProvider,
      posMode: true,
      enableDraft: false,
      enableCartSync: true,
      enableSwipeNavigation: false,
      // stageCount=5 lets the orchestrator's _goToStage accept stage 5 (the
      // POS payment step). The orchestrator only builds stage widgets 1-4;
      // stage 5 is rendered via stageContainerBuilder (PosPaymentStep).
      stageCount: 5,
      // POS navigates to the receipt (not the order list), so the post-submit
      // order-list refresh is skipped — preserves the pre-refactor POS
      // behaviour which did not refresh the list. DG-322 Phase 4.
      enableOrderListRefresh: false,
      onStageChange: (stage) {
        if (stage == 3) {
          ref.read(posCheckoutProvider.notifier).resetStage3();
        }
      },
      stage1Builder: (ctx, controller) => Stage1ProductSelectionScreen(
        onContinue: () => controller.goToStage(2),
        onFastPath: _enterFastPath,
        orderStateProvider: posOrderStateProvider,
      ),
      stage2Builder: (ctx, controller) => Stage2CustomerInfoScreen(
        posMode: true,
        onBack: () {
          _writeBackToCart();
          context.pop();
        },
        onContinue: () => controller.goToStage(3),
        onFastPath: _enterFastPath,
        orderStateProvider: posOrderStateProvider,
      ),
      stage3Builder: (ctx, controller) {
        final state = ref.read(posOrderStateProvider);
        final isPickup = state.wizardData.deliveryType == 'pickup';
        if (isPickup && !checkoutState.stage3ShowFullOptions) {
          return PosStage3PickupScreen(
            onDeliverNow: () {
              ref
                  .read(posCheckoutProvider.notifier)
                  .setDeliverImmediately(true);
              controller.goToStage(4);
            },
            onDeliverLater: () {
              ref
                  .read(posCheckoutProvider.notifier)
                  .setDeliverImmediately(false);
              ref
                  .read(posCheckoutProvider.notifier)
                  .setStage3ShowFullOptions(true);
            },
            onFastPath: _enterFastPath,
          );
        }
        return Stage3DeliveryOptionsScreen(
          onBack: isPickup && checkoutState.stage3ShowFullOptions
              ? () {
                  ref.read(posCheckoutProvider.notifier).resetStage3();
                }
              : () => controller.goToStage(2),
          onContinue: () => controller.goToStage(4),
          onFastPath: _enterFastPath,
          orderStateProvider: posOrderStateProvider,
        );
      },
      stage4Builder: (ctx, controller) => PosReviewPanel(
        onBack: () => controller.goToStage(3),
        onContinue: _enterPaymentStep,
        onFastPath: _enterFastPath,
        orderStateProvider: posOrderStateProvider,
      ),
      // The container hosts stages 1-4 AND the POS payment step (stage 5).
      // Stage 5 is POS-specific and stays in this file (DG-322 Phase 4 §14);
      // the orchestrator renders it via this builder closure so the
      // orchestrator stays mounted and `submitOrder` remains callable from
      // the payment step's pay-now/pay-later handlers.
      stageContainerBuilder: (ctx, stages, currentStage) {
        // Watch the rebuild signal so the stage container re-reads the
        // PosCheckoutPaymentController's plain fields (selectedPaymentMethod,
        // paidAmount, isProcessing, ...) on every bump. Replaces the
        // pre-migration `setState(() {})` rebuild (DG-404 Phase 4.5).
        ref.watch(posCheckoutRebuildProvider);
        final stageCheckoutState = ref.watch(posCheckoutProvider);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: currentStage == 5
              ? PosPaymentStepBuilder(
                  controller: _payment,
                  // DG-370 Phase 2 (FR2/AC2/AC6): forward the POS order state
                  // provider so Stage 5 renders the same order summary cards
                  // as Stage 4 (PosReviewPanel).
                  orderStateProvider: posOrderStateProvider,
                ).build(
                  context,
                  deliverImmediately: stageCheckoutState.posDeliverImmediately,
                  mounted: mounted,
                  onChanged: () =>
                      ref.read(posCheckoutRebuildProvider.notifier).bump(),
                )
              : (currentStage >= 1 && currentStage <= 4
                    ? stages[currentStage - 1]
                    : const SizedBox.shrink()),
        );
      },
      onUploadPendingPhotos: (ref, order, state) =>
          _payment.uploadOrderPhotos(ref, order, state),
      onAfterSubmit: (hookCtx, order) async {
        // POS-specific post-submission: create payment transactions (unless
        // skipPayment / pay-later), clear cart, invalidate product/stock
        // providers.
        await _payment.createPaymentTransactions(
          order,
          _payment.selectedPaymentMethod,
          hookCtx.ref,
        );
        if (identical(hookCtx.ref.read(posOrderStateProvider), hookCtx.state)) {
          hookCtx.ref
              .read(posCheckoutProvider.notifier)
              .markNavigatingAfterCheckout();
          _payment.postSubmitCleanup(hookCtx.ref);
          hookCtx.ref.read(posOrderStateProvider.notifier).reset();
        }
      },
      onNavigateAfterSubmit: (ctx, orderRef) {
        ctx.pushReplacement('/pos/receipt/$orderRef');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);
    final navigatingAfterCheckout = ref
        .watch(posCheckoutProvider)
        .navigatingAfterCheckout;

    if (cart.items.isEmpty && !navigatingAfterCheckout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/pos');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.thanhToan),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: OrdersLabels.backToCart,
          onPressed: () {
            _writeBackToCart();
            context.pop();
          },
        ),
        actions: [
          DiscardFormDraftAction(
            isDirty: ref.watch(posOrderStateProvider).items.isNotEmpty,
            onDiscard: _discardCheckout,
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      // The orchestrator is always mounted (stages 1-4 + the POS payment
      // step rendered via stageContainerBuilder). Keeping it mounted across
      // stage 5 keeps `submitOrder` callable from the payment step handlers.
      body: OrderCreationOrchestrator(
        key: _orchestratorKey,
        config: _buildConfig(),
      ),
    );
  }
}
