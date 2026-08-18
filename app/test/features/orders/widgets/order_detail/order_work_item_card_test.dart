import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_work_item_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

WorkItem _item({
  bool isBirthday = false,
  int? age,
  String notes = '',
  Map<String, dynamic> attributes = const {},
  String productName = 'Bánh kem',
}) {
  return WorkItem(
    id: '1',
    orderId: 'ORD-1',
    productName: productName,
    isBirthday: isBirthday,
    age: age,
    notes: notes,
    attributes: attributes,
  );
}

Future<void> _pump(WidgetTester tester, WorkItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OrderWorkItemCard(
          item: item,
          onTransition: null,
          photos: const [],
          baseUrl: 'http://test.local:8000',
          onTap: null,
        ),
      ),
    ),
  );
}

void main() {
  group('OrderWorkItemCard — birthday / age / candle (FR4 / AC3)', () {
    testWidgets('shows birthday emoji, age "X tuổi", and candle type',
        (tester) async {
      await _pump(
        tester,
        _item(
          isBirthday: true,
          age: 3,
          attributes: const {'candle_type': 'nen_so'},
        ),
      );

      expect(find.textContaining('Sinh nhật'), findsOneWidget);
      expect(find.textContaining('3 tuổi'), findsOneWidget);
      expect(find.text('${VN.packCandles}: ${VN.candleTypeNenSo}'),
          findsOneWidget);
    });

    testWidgets('shows candle type label for nen_xoan', (tester) async {
      await _pump(
        tester,
        _item(attributes: const {'candle_type': 'nen_xoan'}),
      );

      expect(find.text('${VN.packCandles}: ${VN.candleTypeNenXoan}'),
          findsOneWidget);
    });

    testWidgets('does NOT show candle line for khong_nen', (tester) async {
      await _pump(
        tester,
        _item(attributes: const {'candle_type': 'khong_nen'}),
      );

      expect(find.textContaining(VN.packCandles), findsNothing);
    });

    testWidgets('does NOT show candle line when candle_type absent',
        (tester) async {
      await _pump(tester, _item());

      expect(find.textContaining(VN.packCandles), findsNothing);
    });

    testWidgets('shows notes when present', (tester) async {
      await _pump(tester, _item(notes: 'Không đường'));

      expect(find.text('Không đường'), findsOneWidget);
    });

    testWidgets('does NOT show notes when empty', (tester) async {
      await _pump(tester, _item(notes: ''));

      expect(find.text('Không đường'), findsNothing);
    });

    testWidgets('shows birthday label without age when age is null',
        (tester) async {
      await _pump(tester, _item(isBirthday: true));

      expect(find.text('Sinh nhật'), findsOneWidget);
      expect(find.textContaining('tuổi'), findsNothing);
    });
  });
}