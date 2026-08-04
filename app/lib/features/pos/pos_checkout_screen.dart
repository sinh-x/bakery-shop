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
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/pos/widgets/pos_checkout_payment_controller.dart';
import '../../features/pos/widgets/pos_payment_step_builder.dart';
import '../../features/pos/widgets/pos_review_panel.dart';
import '../../features/pos/widgets/pos_stage3_pickup_screen.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/pos_provider.dart';
import '../../shared/labels/orders.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../pos/utils/pos_cart_wizard_sync.dart';

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
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  bool _navigatingAfterCheckout = false;
  bool _posStateInitialized = false;
  bool _posDeliverImmediately = false;
  bool _stage3ShowFullOptions = false;

  late final PosCheckoutPaymentController _payment;
  final GlobalKey<OrderCreationOrchestratorState> _orchestratorKey =
      GlobalKey<OrderCreationOrchestratorState>();

  @override
  void initState() {
    super.initState();
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
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosState();
    });
  }

  void _initPosState() {
    if (_posStateInitialized) return;
    _posStateInitialized = true;

    final posNotifier = ref.read(posOrderStateProvider.notifier);
    const wizardData = OrderWizardData(
      customerName: VN.khachLe,
      source: VN.taiTiemPOS,
      deliveryType: 'pickup',
    );
    posNotifier.updateWizardData(wizardData);
    posNotifier.updateSource(VN.taiTiemPOS);
    final posDue = posDefaultDueDateTime(DateTime.now());
    posNotifier.updateDueDate(DateTime(posDue.year, posDue.month, posDue.day));
    posNotifier.updateDueTime(TimeOfDay(hour: posDue.hour, minute: posDue.minute));
    posNotifier.goToStage(1);
  }

  void _goToStage(int stage) {
    if (stage == 3) {
      _posDeliverImmediately = false;
      _stage3ShowFullOptions = false;
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

  void _confirmClearCart() {
    showClearCartDialog(
      context: context,
      onConfirm: () {
        ref.read(posCartProvider.notifier).clearCart();
      },
    );
  }

  OrderCreationConfig _buildConfig() {
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
          _posDeliverImmediately = false;
          _stage3ShowFullOptions = false;
        }
      },
      stage1Builder: (ctx, controller) => Stage1ProductSelectionScreen(
        onContinue: () => controller.goToStage(2),
        orderStateProvider: posOrderStateProvider,
      ),
      stage2Builder: (ctx, controller) => Stage2CustomerInfoScreen(
        posMode: true,
        onBack: () {
          _writeBackToCart();
          context.pop();
        },
        onContinue: () => controller.goToStage(3),
        orderStateProvider: posOrderStateProvider,
      ),
      stage3Builder: (ctx, controller) {
        final state = ref.read(posOrderStateProvider);
        final isPickup = state.wizardData.deliveryType == 'pickup';
        if (isPickup && !_stage3ShowFullOptions) {
          return PosStage3PickupScreen(
            onDeliverNow: () {
              _posDeliverImmediately = true;
              controller.goToStage(4);
            },
            onDeliverLater: () {
              _posDeliverImmediately = false;
              _stage3ShowFullOptions = true;
              setState(() {});
            },
          );
        }
        return Stage3DeliveryOptionsScreen(
          onBack: isPickup && _stage3ShowFullOptions
              ? () {
                  _posDeliverImmediately = false;
                  _stage3ShowFullOptions = false;
                  setState(() {});
                }
              : () => controller.goToStage(2),
          onContinue: () => controller.goToStage(4),
          orderStateProvider: posOrderStateProvider,
        );
      },
      stage4Builder: (ctx, controller) => PosReviewPanel(
        onBack: () => controller.goToStage(3),
        onContinue: _enterPaymentStep,
        orderStateProvider: posOrderStateProvider,
      ),
      // The container hosts stages 1-4 AND the POS payment step (stage 5).
      // Stage 5 is POS-specific and stays in this file (DG-322 Phase 4 §14);
      // the orchestrator renders it via this builder closure so the
      // orchestrator stays mounted and `submitOrder` remains callable from
      // the payment step's pay-now/pay-later handlers.
      stageContainerBuilder: (ctx, stages, currentStage) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: currentStage == 5
            ? PosPaymentStepBuilder(controller: _payment).build(
                context,
                deliverImmediately: _posDeliverImmediately,
                mounted: mounted,
                onChanged: () => setState(() {}),
              )
            : (currentStage >= 1 && currentStage <= 4
                ? stages[currentStage - 1]
                : const SizedBox.shrink()),
      ),
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
        _payment.postSubmitCleanup(hookCtx.ref);
        _navigatingAfterCheckout = true;
      },
      onNavigateAfterSubmit: (ctx, orderRef) {
        ctx.pushReplacement('/pos/receipt/$orderRef');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);

    if (cart.items.isEmpty && !_navigatingAfterCheckout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/pos');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.thanhToan),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: VN.backToCart,
          onPressed: () {
            _writeBackToCart();
            context.pop();
          },
        ),
        actions: [
          TextButton.icon(
            onPressed: _confirmClearCart,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text(VN.clearCart),
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