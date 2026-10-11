// DG-322 Phase 4: thin wrapper over OrderCreationOrchestrator for stages
// 1-4. buildPosCheckoutConfig supplies POS-specific stage presentation
// and submission hooks; this screen owns the draft/controller lifetimes.
// The orchestrator owns the shared stage shell, indicator, and submission
// spine; stage-5 payment state/handlers stay in PosCheckoutPaymentController.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/orders/widgets/order_creation_orchestrator.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/providers/order_submission_guard_notifier.dart';
import '../../features/orders/providers/order_draft_contexts.dart';
import '../../features/pos/widgets/pos_checkout_payment_controller.dart';
import 'widgets/pos_checkout_config_builder.dart';
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
      // Successful cleanup resets live state; it must not replace the
      // submitted retained snapshot before the shared spine clears it.
      if (ref.read(posCheckoutProvider).navigatingAfterCheckout) return;
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
        config: buildPosCheckoutConfig(
          ref: ref,
          context: context,
          payment: _payment,
          isMounted: () => mounted,
          enterFastPath: _enterFastPath,
          enterPaymentStep: _enterPaymentStep,
          writeBackToCart: _writeBackToCart,
        ),
      ),
    );
  }
}
