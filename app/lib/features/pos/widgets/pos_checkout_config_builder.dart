import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/order/order_create_state_provider.dart';
import '../../orders/widgets/order_creation_config.dart';
import '../../orders/widgets/stage1_product_selection_screen.dart';
import '../../orders/widgets/stage2_customer_info_screen.dart';
import '../../orders/widgets/stage3_delivery_options_screen.dart';
import '../providers/pos_checkout_notifier.dart';
import 'pos_checkout_payment_controller.dart';
import 'pos_payment_step_builder.dart';
import 'pos_review_panel.dart';
import 'pos_stage3_pickup_screen.dart';

/// POS presentation and submission hooks for the shared order wizard.
///
/// The host owns payment-controller and draft lifetimes. Build a fresh config
/// each host build so pickup options use the current checkout state. Keep the
/// orchestrator mounted during payment so its submission spine remains callable.
OrderCreationConfig buildPosCheckoutConfig({
  required WidgetRef ref,
  required BuildContext context,
  required PosCheckoutPaymentController payment,
  required bool Function() isMounted,
  required VoidCallback enterFastPath,
  required VoidCallback enterPaymentStep,
  required VoidCallback writeBackToCart,
}) {
  final checkoutState = ref.read(posCheckoutProvider);
  return OrderCreationConfig(
    orderStateProvider: posOrderStateProvider,
    posMode: true,
    enableDraft: false,
    enableCartSync: true,
    enableSwipeNavigation: false,
    // The shared spine builds stages 1-4; the POS container also hosts payment.
    stageCount: 5,
    // POS navigates to the receipt rather than the normal order list.
    enableOrderListRefresh: false,
    onStageChange: (stage) {
      if (stage == 3) {
        ref.read(posCheckoutProvider.notifier).resetStage3();
      }
    },
    stage1Builder: (ctx, controller) => Stage1ProductSelectionScreen(
      onContinue: () => controller.goToStage(2),
      onFastPath: enterFastPath,
      orderStateProvider: posOrderStateProvider,
    ),
    stage2Builder: (ctx, controller) => Stage2CustomerInfoScreen(
      posMode: true,
      onBack: () {
        writeBackToCart();
        context.pop();
      },
      onContinue: () => controller.goToStage(3),
      onFastPath: enterFastPath,
      orderStateProvider: posOrderStateProvider,
    ),
    stage3Builder: (ctx, controller) {
      final state = ref.read(posOrderStateProvider);
      final isPickup = state.wizardData.deliveryType == 'pickup';
      if (isPickup && !checkoutState.stage3ShowFullOptions) {
        return PosStage3PickupScreen(
          onDeliverNow: () {
            ref.read(posCheckoutProvider.notifier).setDeliverImmediately(true);
            controller.goToStage(4);
          },
          onDeliverLater: () {
            ref.read(posCheckoutProvider.notifier).setDeliverImmediately(false);
            ref
                .read(posCheckoutProvider.notifier)
                .setStage3ShowFullOptions(true);
          },
          onFastPath: enterFastPath,
        );
      }
      return Stage3DeliveryOptionsScreen(
        onBack: isPickup && checkoutState.stage3ShowFullOptions
            ? () {
                ref.read(posCheckoutProvider.notifier).resetStage3();
              }
            : () => controller.goToStage(2),
        onContinue: () => controller.goToStage(4),
        onFastPath: enterFastPath,
        orderStateProvider: posOrderStateProvider,
      );
    },
    stage4Builder: (ctx, controller) => PosReviewPanel(
      onBack: () => controller.goToStage(3),
      onContinue: enterPaymentStep,
      onFastPath: enterFastPath,
      orderStateProvider: posOrderStateProvider,
    ),
    stageContainerBuilder: (ctx, stages, currentStage) {
      // Re-read the controller's plain fields on every payment rebuild signal.
      ref.watch(posCheckoutRebuildProvider);
      final stageCheckoutState = ref.watch(posCheckoutProvider);
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: currentStage == 5
            ? PosPaymentStepBuilder(
                controller: payment,
                orderStateProvider: posOrderStateProvider,
              ).build(
                context,
                deliverImmediately: stageCheckoutState.posDeliverImmediately,
                mounted: isMounted(),
                onChanged: () =>
                    ref.read(posCheckoutRebuildProvider.notifier).bump(),
              )
            : (currentStage >= 1 && currentStage <= 4
                  ? stages[currentStage - 1]
                  : const SizedBox.shrink()),
      );
    },
    onUploadPendingPhotos: (ref, order, state) =>
        payment.uploadOrderPhotos(ref, order, state),
    onAfterSubmit: (hookCtx, order) async {
      // Preserve pay-later handling and newer same-context drafts during cleanup.
      await payment.createPaymentTransactions(
        order,
        payment.selectedPaymentMethod,
        hookCtx.ref,
      );
      if (identical(hookCtx.ref.read(posOrderStateProvider), hookCtx.state)) {
        hookCtx.ref
            .read(posCheckoutProvider.notifier)
            .markNavigatingAfterCheckout();
        payment.postSubmitCleanup(hookCtx.ref);
        hookCtx.ref.read(posOrderStateProvider.notifier).reset();
      }
    },
    onNavigateAfterSubmit: (ctx, orderRef) {
      ctx.pushReplacement('/pos/receipt/$orderRef');
    },
  );
}
