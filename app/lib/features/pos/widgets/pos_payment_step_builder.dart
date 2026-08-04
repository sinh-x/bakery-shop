import 'package:flutter/material.dart';

import 'pos_checkout_payment_controller.dart';
import 'pos_payment_step.dart';

/// Builds the [PosPaymentStep] widget for stage 5 from a
/// [PosCheckoutPaymentController] snapshot. Extracted from the controller
/// (DG-322 / CQ-4) so the controller file stays under the 400-line provider
/// threshold; the widget wiring is pure presentation and does not need
/// controller-owned state.
class PosPaymentStepBuilder {
  const PosPaymentStepBuilder({required this.controller});

  final PosCheckoutPaymentController controller;

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