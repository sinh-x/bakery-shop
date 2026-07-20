import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/pos/widgets/pos_payment_step.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

void main() {
  group('PosPaymentStep target account selector (DG-244 Phase 2)', () {
    Widget buildStep({
      required String paymentMethod,
      String? selectedTargetAccount,
      ValueChanged<String?>? onTargetAccountChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PosPaymentStep(
            orderTotal: 100000,
            initialAmount: 100000,
            hasTienRut: false,
            tienRutAmount: 0,
            selectedPaymentMethod: paymentMethod,
            selectedTargetAccount: selectedTargetAccount,
            isProcessing: false,
            onPaymentMethodChanged: (_) {},
            onAmountChanged: (_) {},
            onTienRutAmountChanged: (_) {},
            onTargetAccountChanged: onTargetAccountChanged,
            onBack: () {},
            onPayNow: () {},
            onPayLater: () {},
          ),
        ),
      );
    }

    /// Asserts the dropdown's full set of option values by inspecting the
    /// inner [DropdownButton] widget (the FormField wrapper does not expose
    /// items as a public getter).
    void expectDropdownItems(WidgetTester tester, List<String?> expected) {
      final dropdown = tester.widget<DropdownButton<String?>>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String?>),
          matching: find.byType(DropdownButton<String?>),
        ),
      );
      final itemValues = dropdown.items!.map((i) => i.value).toList();
      expect(itemValues, expected);
    }

    testWidgets('AC1/FR7: cash method does not show the target account dropdown',
        (tester) async {
      await tester.pumpWidget(buildStep(paymentMethod: 'cash'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
      expect(find.text(VN.paymentTargetAccountLabel), findsNothing);
    });

    testWidgets('AC1/FR7: transfer method shows the TK đích dropdown with empty default and both VCB options',
        (tester) async {
      await tester.pumpWidget(buildStep(paymentMethod: 'transfer'));
      await tester.pumpAndSettle();

      expect(find.text(VN.paymentTargetAccountLabel), findsOneWidget);
      // The "no account" label is rendered as the default selected item.
      expect(find.text(VN.paymentNoAccount), findsOneWidget);
      expectDropdownItems(tester, [null, VN.paymentSourcePhuongVCB, VN.paymentSourceAnVCB]);
    });

    testWidgets('FR2: dropdown defaults to empty (no pre-selection)',
        (tester) async {
      await tester.pumpWidget(buildStep(paymentMethod: 'transfer'));
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown.initialValue, isNull);
    });

    testWidgets('FR6: pre-selected target account is reflected in the dropdown value',
        (tester) async {
      await tester.pumpWidget(
        buildStep(
          paymentMethod: 'transfer',
          selectedTargetAccount: VN.paymentSourceAnVCB,
        ),
      );
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown.initialValue, VN.paymentSourceAnVCB);
    });

    testWidgets('AC7: selecting an account fires onTargetAccountChanged with the value',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        buildStep(
          paymentMethod: 'transfer',
          onTargetAccountChanged: (v) => captured = v,
        ),
      );
      await tester.pumpAndSettle();

      // Tap the dropdown to open the menu.
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.paymentSourcePhuongVCB).last);
      await tester.pumpAndSettle();

      expect(captured, VN.paymentSourcePhuongVCB);
    });

    testWidgets('NFR3: dropdown has no validator (empty selection allowed)',
        (tester) async {
      await tester.pumpWidget(buildStep(paymentMethod: 'transfer'));
      await tester.pumpAndSettle();

      final formField = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      // No validator set → empty/null is a valid submission (FR2/NFR3).
      expect(formField.validator, isNull);
    });
  });
}