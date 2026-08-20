import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/candle_type_radio_group.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Widget tests for the shared `CandleTypeRadioGroup` (review finding CQ-2).
///
/// Coverage required by the review:
/// 1. Renders with the default "Không nến" selection (AC1/AC7 default).
/// 2. Selecting a different option updates the value via `onChanged`.
/// 3. All 4 candle type options are present.
void main() {
  Widget harness({
    required String? groupValue,
    ValueChanged<String?>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CandleTypeRadioGroup(
          groupValue: groupValue,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets(
    'all 4 candle type options are present',
    (tester) async {
      await tester.pumpWidget(harness(groupValue: 'khong_nen'));
      await tester.pumpAndSettle();

      expect(find.byType(CandleTypeRadioGroup), findsOneWidget);
      // DG-361 Phase 1: layout changed from Column+RadioListTile to Wrap+Radio.
      // A Wrap container holds the four inline Radio options.
      expect(find.byType(Wrap), findsWidgets);
      expect(find.byType(Radio<String>), findsNWidgets(4));
      expect(find.text(OrdersLabels.candleTypeNenSo), findsOneWidget);
      expect(find.text(OrdersLabels.candleTypeNenXoan), findsOneWidget);
      expect(find.text(OrdersLabels.candleTypeNenNho), findsOneWidget);
      expect(find.text(OrdersLabels.candleTypeKhongNen), findsOneWidget);
    },
  );

  testWidgets(
    'renders with default "Không nến" groupValue (AC1/AC7 default)',
    (tester) async {
      // The default selection passed by all three call sites is 'khong_nen'.
      // We assert the widget accepts it without error and renders the label.
      await tester.pumpWidget(harness(groupValue: 'khong_nen'));
      await tester.pumpAndSettle();

      expect(find.byType(CandleTypeRadioGroup), findsOneWidget);
      expect(find.text(OrdersLabels.candleTypeKhongNen), findsOneWidget);
      // The four values map to the four expected constants exactly.
      final radioValues = tester
          .widgetList<Radio<String>>(find.byType(Radio<String>))
          .map((r) => r.value)
          .toSet();
      expect(radioValues, {'nen_so', 'nen_xoan', 'nen_nho', 'khong_nen'});
    },
  );

  testWidgets(
    'DG-361 AC1: renders options inside a Wrap (horizontal layout, not RadioListTile)',
    (tester) async {
      await tester.pumpWidget(harness(groupValue: 'nen_so'));
      await tester.pumpAndSettle();

      // The widget tree must use Wrap + Radio, not the legacy vertical
      // RadioListTile (FR1/AC1).
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byType(Wrap), findsWidgets);
      expect(find.byType(Radio<String>), findsNWidgets(4));
    },
  );

  testWidgets(
    'selecting a different option invokes onChanged with the new value',
    (tester) async {
      String? selected = 'khong_nen';
      await tester.pumpWidget(
        harness(
          groupValue: selected,
          onChanged: (v) => selected = v,
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Nến số" to change selection away from the default.
      await tester.tap(find.text(OrdersLabels.candleTypeNenSo));
      await tester.pump();

      expect(selected, 'nen_so');

      // Tap "Nến xoắn" to change selection again.
      await tester.tap(find.text(OrdersLabels.candleTypeNenXoan));
      await tester.pump();

      expect(selected, 'nen_xoan');
    },
  );
}