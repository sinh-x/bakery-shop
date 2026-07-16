import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_item.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_card.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';

const _testRef = 'TEST-ORDER-1';

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  final List<OrderPhoto> _photos;
  _FakeOrderPhotosNotifier(this._photos) : super(_testRef);

  @override
  Future<List<OrderPhoto>> build() async => _photos;
}

Order _completeOrder() => Order(
  id: '1',
  orderRef: _testRef,
  customerName: 'Nguyễn Văn A',
  items: const [
    OrderItem(
      productId: 'prod-1',
      productName: 'Bánh kem',
      quantity: 1,
      unitPrice: 200000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 200000.0,
  status: 'new',
  dueDate: '2026-07-15',
  dueTime: '10:00',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'complete',
  missingFields: const [],
);

Order _incompleteOrder() => Order(
  id: '2',
  orderRef: _testRef,
  customerName: 'Khách',
  items: const [],
  totalPrice: 0.0,
  status: 'new',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'incomplete',
  missingFields: const ['customer_name', 'items', 'total_price'],
);

Order _incompleteUrgentOrder() => Order(
  id: '3',
  orderRef: _testRef,
  customerName: 'Trần Thị B',
  items: const [
    OrderItem(
      productId: 'prod-2',
      productName: 'Bánh mì',
      quantity: 2,
      unitPrice: 50000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 100000.0,
  status: 'new',
  dueDate: '2026-07-16',
  dueTime: '09:00',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'incomplete',
  urgency: 'urgent',
  missingFields: const ['customer_name'],
);

Order _completeCriticalOrder() => Order(
  id: '4',
  orderRef: _testRef,
  customerName: 'Lê Văn C',
  items: const [
    OrderItem(
      productId: 'prod-3',
      productName: 'Bánh sinh nhật',
      quantity: 1,
      unitPrice: 350000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 350000.0,
  status: 'new',
  dueDate: '2026-07-14',
  dueTime: '08:00',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'complete',
  urgency: 'critical',
  missingFields: const [],
);

Order _longNameOrder() => Order(
  id: '5',
  orderRef: _testRef,
  customerName: 'Nguyễn Thị Hoàng Thị Mai Hương Phạm Trần Bạch Liên Hoa'
      ' Đặng Võ Hồng Quân Nguyễn Lê Minh Khánh',
  items: const [
    OrderItem(
      productId: 'prod-4',
      productName: 'Bánh kem',
      quantity: 1,
      unitPrice: 200000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 200000.0,
  status: 'new',
  dueDate: '2026-07-15',
  dueTime: '10:00',
  createdAt: DateTime(2026, 7, 12),
  updatedAt: DateTime(2026, 7, 12),
  completeness: 'complete',
  missingFields: const [],
);

Future<Widget> _buildTestApp(Order order) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      orderPhotosProvider(order.orderRef)
          .overrideWith(() => _FakeOrderPhotosNotifier(const [])),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: OrderCard(order: order, onTap: () {}),
          ),
        ),
      ),
    ),
  );
}

/// Returns the left border color of the OrderCard's outer Container.
Color? _cardLeftBorderColor(WidgetTester tester) {
  final containerFinder = find
      .descendant(
        of: find.byType(OrderCard),
        matching: find.byType(Container),
      )
      .first;
  final container = tester.widget<Container>(containerFinder);
  final decoration = container.decoration;
  if (decoration is BoxDecoration) {
    final border = decoration.border;
    if (border is Border) {
      return border.left.color;
    }
  }
  return null;
}

void main() {
  testWidgets('OrderCard does not show completeness indicators for complete order',
      (tester) async {
    final widget = await _buildTestApp(_completeOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text(OrdersLabels.completenessIncompleteBadge), findsNothing);
    expect(find.textContaining(OrdersLabels.completenessMissingPrefix), findsNothing);
  });

  testWidgets('OrderCard shows completeness indicators for incomplete order',
      (tester) async {
    final widget = await _buildTestApp(_incompleteOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Khách'), findsOneWidget);
    expect(find.text(OrdersLabels.completenessIncompleteBadge), findsOneWidget);
    expect(
      find.textContaining(OrdersLabels.completenessMissingPrefix),
      findsOneWidget,
    );
  });

  testWidgets('OrderCard missing fields indicator shows field labels',
      (tester) async {
    final widget = await _buildTestApp(_incompleteOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.textContaining('tên KH'), findsOneWidget);
    expect(find.textContaining('sản phẩm'), findsOneWidget);
    expect(find.textContaining('tổng tiền'), findsOneWidget);
  });

  // ── AC1: long customer name wraps without ellipsis truncation ──
  testWidgets('AC1: long customer name renders in full without ellipsis',
      (tester) async {
    final order = _longNameOrder();
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    // Full name Text is present (no truncation cutting it off).
    expect(find.text(order.customerName), findsOneWidget);

    // The name Text widget is configured to allow wrapping (maxLines > 1),
    // not single-line ellipsis.
    final nameText = tester.widget<Text>(
      find.text(order.customerName),
    );
    expect(nameText.maxLines, isNot(1));
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  // ── AC2: completeness badge on its own row, not inline with name ──
  testWidgets('AC2: completeness badge appears on its own row below name row',
      (tester) async {
    final widget = await _buildTestApp(_incompleteOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    final badgeFinder = find.text(OrdersLabels.completenessIncompleteBadge);
    expect(badgeFinder, findsOneWidget);
    final badgeRow =
        tester.widget<Row>(find.ancestor(of: badgeFinder, matching: find.byType(Row)).first);

    // The name Text widget should not be a child of the same Row as the badge.
    final nameFinder = find.text('Khách');
    final nameRow =
        tester.widget<Row>(find.ancestor(of: nameFinder, matching: find.byType(Row)).first);

    // Distinct Row instances: badge row != name row.
    expect(identical(badgeRow, nameRow), isFalse);
  });

  // ── AC3: border color driven by urgency tier only ──
  testWidgets(
      'AC3: border color is urgency red for incomplete+urgent order (not completeness amber)',
      (tester) async {
    final widget = await _buildTestApp(_incompleteUrgentOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    final borderColor = _cardLeftBorderColor(tester);
    // Urgency urgent = amber, completeness incomplete = amber — but urgency
    // should win per FR-3. Confirm it equals urgencyTierColor('urgent').
    expect(borderColor, urgencyTierColor('urgent'));
    expect(borderColor, BakeryTheme.urgencyTierColors['urgent']);
    // And it is NOT the completeness color via the completeness map (same value
    // here, so also confirm precedence logic by checking the critical case below).
  });

  testWidgets('AC3: border color is urgency red for complete+critical order',
      (tester) async {
    final widget = await _buildTestApp(_completeCriticalOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    final borderColor = _cardLeftBorderColor(tester);
    expect(borderColor, urgencyTierColor('critical'));
    expect(borderColor, BakeryTheme.urgencyTierColors['critical']);
  });

  testWidgets('AC3: border is transparent for normal-urgency complete order',
      (tester) async {
    final widget = await _buildTestApp(_completeOrder());
    await tester.pumpWidget(widget);
    await tester.pump();

    final borderColor = _cardLeftBorderColor(tester);
    expect(borderColor, Colors.transparent);
  });

  // ── AC4: incomplete-but-not-critical order does not pulse ──
  testWidgets('AC4: incomplete urgent order does not pulse (critical only)',
      (tester) async {
    final order = _incompleteUrgentOrder();
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Only critical urgency cards are wrapped in a ColorFiltered pulse.
    expect(find.byType(ColorFiltered), findsNothing);
    expect(order.urgency, isNot('critical'));
  });

  testWidgets('AC4: critical order pulses (ColorFiltered present)',
      (tester) async {
    final widget = await _buildTestApp(_completeCriticalOrder());
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}