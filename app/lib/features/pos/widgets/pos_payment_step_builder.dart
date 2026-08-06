import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'pos_checkout_payment_controller.dart';
import 'pos_payment_step.dart';

/// Builds the [PosPaymentStep] widget for stage 5 from a
/// [PosCheckoutPaymentController] snapshot. Extracted from the controller
/// (DG-322 / CQ-4) so the controller file stays under the 400-line provider
/// threshold; the widget wiring is pure presentation and does not need
/// controller-owned state.
///
/// Since DG-370 Phase 2, this builder also forwards the
/// `orderStateProvider` so [PosPaymentStep] can render the order summary
/// section (FR2/AC2/AC6).
class PosPaymentStepBuilder {
  const PosPaymentStepBuilder({
    required this.controller,
    required this.orderStateProvider,
  });

  final PosCheckoutPaymentController controller;

  /// The order-create state provider used to render the order summary cards
  /// in Stage 5 (DG-370 Phase 2, FR2). Same provider used by Stage 4
  /// (`PosReviewPanel`).
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      orderStateProvider;

  Widget build(
    BuildContext context, {
    required bool deliverImmediately,
    required bool mounted,
    required VoidCallback onChanged,
  }) {
    return PosPaymentStep(
      key: const ValueKey('pos-payment'),
      orderTotal: controller.cartTotal,
      initialAmount: controller.paidAmount,
      hasTienRut: controller.hasTienRut,
      tienRutAmount: controller.tienRutAmount,
      selectedPaymentMethod: controller.selectedPaymentMethod,
      selectedTargetAccount: controller.selectedTargetAccount,
      isProcessing: controller.isProcessing,
      orderStateProvider: orderStateProvider,
      onPaymentMethodChanged: (m) {
        controller.onPaymentMethodChanged(m);
        onChanged();
      },
      onAmountChanged: (a) {
        controller.onAmountChanged(a);
        onChanged();
      },
      onTienRutAmountChanged: (a) {
        controller.onTienRutAmountChanged(a);
        onChanged();
      },
      onTargetAccountChanged: (a) {
        controller.onTargetAccountChanged(a);
        onChanged();
      },
      onBack: () {
        controller.backFromPaymentStep();
        onChanged();
      },
      onPayNow: () {
        controller.handlePayNow(
          context,
          deliverImmediately: deliverImmediately,
          mounted: mounted,
        );
        onChanged();
      },
      onPayLater: () {
        controller.handlePayLater(context, mounted: mounted);
        onChanged();
      },
    );
  }
}