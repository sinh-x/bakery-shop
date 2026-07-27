import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/order_item_markup_line.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('OrderItemMarkupLine (DG-296 Phase 5, FR7/AC6)', () {
    testWidgets('shows markup amount when assignedPrice < unitPrice', (tester) async {
      await tester.pumpWidget(_wrap(const OrderItemMarkupLine(
        unitPrice: 250000,
        assignedPrice: 200000,
      )));
      await tester.pump();
      expect(find.textContaining(VN.markupAmount), findsOneWidget);
      // 250000 - 200000 = 50000 → "50.000đ"
      expect(find.text('Phần cộng thêm: 50.000đ'), findsOneWidget);
    });

    testWidgets('renders nothing when assignedPrice is null (historical)', (tester) async {
      await tester.pumpWidget(_wrap(const OrderItemMarkupLine(
        unitPrice: 250000,
        assignedPrice: null,
      )));
      await tester.pump();
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining(VN.markupAmount), findsNothing);
    });

    testWidgets('renders nothing when assignedPrice == unitPrice (no markup)', (tester) async {
      await tester.pumpWidget(_wrap(const OrderItemMarkupLine(
        unitPrice: 200000,
        assignedPrice: 200000,
      )));
      await tester.pump();
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining(VN.markupAmount), findsNothing);
    });

    testWidgets('renders nothing when assignedPrice > unitPrice (invalid/upward)', (tester) async {
      await tester.pumpWidget(_wrap(const OrderItemMarkupLine(
        unitPrice: 150000,
        assignedPrice: 200000,
      )));
      await tester.pump();
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.textContaining(VN.markupAmount), findsNothing);
    });
  });
}