// DG-322 / CQ-7 — direct widget test for the extracted
// `PosPaymentStepBuilder.build` (CQ-4 extraction). Verifies the builder wires
// the controller snapshot into `PosPaymentStep` and forwards the public
// callbacks to the controller's mutation methods. The builder is pure
// presentation glue, so a single render + interaction test covers it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/pos/widgets/pos_checkout_payment_controller.dart';
import 'package:bakery_app/features/pos/widgets/pos_payment_step.dart';
import 'package:bakery_app/features/pos/widgets/pos_payment_step_builder.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class _BuilderHost extends ConsumerWidget {
  const _BuilderHost({
    required this.deliverImmediately,
    required this.mountedFlag,
    required this.onChangedFlag,
  });

  final bool deliverImmediately;
  final bool mountedFlag;
  final VoidCallback onChangedFlag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = PosCheckoutPaymentController(
      ref: ref,
      submitOrder: ({status, paymentMethod}) async => false,
      resolveDeliveryType: () => 'pickup',
      goToStage: (_) {},
      writeBackToCart: () {},
    );
    // Force a deterministic payment state without driving the full POS
    // enter-payment-step pipeline (which would need a seeded cart).
    controller.onPaymentMethodChanged('transfer');
    controller.onAmountChanged(120000);

    return MaterialApp(
      home: Scaffold(
        body: PosPaymentStepBuilder(controller: controller).build(
          context,
          deliverImmediately: deliverImmediately,
          mounted: mountedFlag,
          onChanged: onChangedFlag,
        ),
      ),
    );
  }
}

void main() {
  group('PosPaymentStepBuilder.build (DG-322 / CQ-7)', () {
    testWidgets('renders PosPaymentStep wired to the controller snapshot',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _BuilderHost(
            deliverImmediately: false,
            mountedFlag: true,
            onChangedFlag: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PosPaymentStep), findsOneWidget);
      // The transfer method reveals the target-account dropdown (FR7).
      expect(find.text(VN.paymentTargetAccountLabel), findsOneWidget);
    });

    testWidgets('onChanged fires after a payment-method change',
        (tester) async {
      bool changed = false;
      await tester.pumpWidget(
        ProviderScope(
          child: _BuilderHost(
            deliverImmediately: false,
            mountedFlag: true,
            onChangedFlag: () => changed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the cash option in the payment method selector.
      await tester.tap(find.text(VN.tienMat).first);
      await tester.pumpAndSettle();

      expect(changed, isTrue);
    });
  });
}