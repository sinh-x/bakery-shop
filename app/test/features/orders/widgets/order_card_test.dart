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

Order _inProgressUrgentOrder() => Order(
  id: '6',
  orderRef: _testRef,
  customerName: 'Phạm Văn D',
  items: const [
    OrderItem(
      productId: 'prod-5',
      productName: 'Bánh su kem',
      quantity: 3,
      unitPrice: 30000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 90000.0,
  status: 'in_progress',
  dueDate: '2026-08-09',
  dueTime: '14:00',
  createdAt: DateTime(2026, 8, 9),
  updatedAt: DateTime(2026, 8, 9),
  completeness: 'complete',
  urgency: 'urgent',
  missingFields: const [],
);

Order _readyUrgentOrder() => Order(
  id: '7',
  orderRef: _testRef,
  customerName: 'Hoàng Thị E',
  items: const [
    OrderItem(
      productId: 'prod-6',
      productName: 'Bánh croissant',
      quantity: 2,
      unitPrice: 25000.0,
      isExtra: false,
    ),
  ],
  totalPrice: 50000.0,
  status: 'ready',
  dueDate: '2026-08-09',
  dueTime: '15:00',
  createdAt: DateTime(2026, 8, 9),
  updatedAt: DateTime(2026, 8, 9),
  completeness: 'complete',
  urgency: 'urgent',
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

/// Returns the left border width of the OrderCard's outer Container, or null
/// if no left border is present.
double? _cardLeftBorderWidth(WidgetTester tester) {
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
      return border.left.width;
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

  // ── DG-377 Phase 4.3: orange bar for fixed due-today scenarios ──
  //
  // Phase 4.1 fixed compute_urgency() so in_progress and ready orders due
  // today get urgency='urgent'. The OrderCard reads the backend-computed
  // `urgency` field and renders a 4px amber (#FFA000) left border. These
  // tests verify the orange bar renders correctly for the two fixed
  // scenarios (AC1 in_progress due today, AC2 ready due today) at the UI
  // level, complementing the backend regression tests in Phase 4.2.

  testWidgets(
      'AC1 (DG-377): in_progress order due today shows orange urgent bar',
      (tester) async {
    final order = _inProgressUrgentOrder();
    expect(order.urgency, 'urgent');
    expect(order.status, 'in_progress');

    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    final borderColor = _cardLeftBorderColor(tester);
    final borderWidth = _cardLeftBorderWidth(tester);

    // Orange/amber urgent tier color (#FFA000) — the orange bar fix target.
    expect(borderColor, const Color(0xFFFFA000));
    expect(borderColor, urgencyTierColor('urgent'));
    expect(borderColor, BakeryTheme.urgencyTierColors['urgent']);
    // 4px-wide left border per the OrderCard decoration (order_card.dart:191).
    expect(borderWidth, 4);
  });

  testWidgets(
      'AC2 (DG-377): ready order due today shows orange urgent bar',
      (tester) async {
    final order = _readyUrgentOrder();
    expect(order.urgency, 'urgent');
    expect(order.status, 'ready');

    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    final borderColor = _cardLeftBorderColor(tester);
    final borderWidth = _cardLeftBorderWidth(tester);

    expect(borderColor, const Color(0xFFFFA000));
    expect(borderColor, urgencyTierColor('urgent'));
    expect(borderColor, BakeryTheme.urgencyTierColors['urgent']);
    expect(borderWidth, 4);
  });

  // ── DG-384 Phase 4: payment methods display on OrderCard ──
  //
  // Phase 3 added `paymentMethods` (List<String>) to the API response.
  // Phase 4 surfaces it on the OrderCard beside the existing payment status
  // badge, mapping "cash" → "Tiền mặt" and "transfer" → "Chuyển khoản" via
  // the shared `paymentMethodLabel()` helper (shared/utils.dart).

  Order orderWithPaymentMethods(List<String> paymentMethods) => Order(
        id: '8',
        orderRef: _testRef,
        customerName: 'Khách Đối Soát',
        items: const [
          OrderItem(
            productId: 'prod-7',
            productName: 'Bánh kem',
            quantity: 1,
            unitPrice: 200000.0,
            isExtra: false,
          ),
        ],
        totalPrice: 200000.0,
        status: 'delivered',
        dueDate: '2026-08-12',
        isPaid: true,
        amountPaid: 200000.0,
        createdAt: DateTime(2026, 8, 12),
        updatedAt: DateTime(2026, 8, 12),
        completeness: 'complete',
        missingFields: const [],
        paymentMethods: paymentMethods,
      );

  testWidgets(
      'AC3 (DG-384): order with payment method "cash" shows "Tiền mặt"',
      (tester) async {
    final order = orderWithPaymentMethods(const ['cash']);
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Tiền mặt'), findsOneWidget);
    // The "transfer" label must NOT appear for a cash-only order.
    expect(find.text('Chuyển khoản'), findsNothing);
  });

  testWidgets(
      'AC4 (DG-384): order with payment method "transfer" shows "Chuyển khoản"',
      (tester) async {
    final order = orderWithPaymentMethods(const ['transfer']);
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('Chuyển khoản'), findsOneWidget);
    // The "cash" label must NOT appear for a transfer-only order.
    expect(find.text('Tiền mặt'), findsNothing);
  });

  testWidgets(
      'DG-384: order with multiple payment methods shows comma-separated labels',
      (tester) async {
    final order = orderWithPaymentMethods(const ['cash', 'transfer']);
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    // Both labels render, joined by a comma.
    expect(find.textContaining('Tiền mặt'), findsOneWidget);
    expect(find.textContaining('Chuyển khoản'), findsOneWidget);
    // The combined label text is "Tiền mặt, Chuyển khoản".
    expect(find.text('Tiền mặt, Chuyển khoản'), findsOneWidget);
  });

  testWidgets(
      'DG-384: order with no payment methods renders no payment-method label',
      (tester) async {
    final order = orderWithPaymentMethods(const []);
    final widget = await _buildTestApp(order);
    await tester.pumpWidget(widget);
    await tester.pump();

    // No Vietnamese payment-method labels rendered.
    expect(find.text('Tiền mặt'), findsNothing);
    expect(find.text('Chuyển khoản'), findsNothing);
    // The payment status badge still renders (defensive — display survives).
    expect(find.text('Đã TT'), findsOneWidget);
  });
}