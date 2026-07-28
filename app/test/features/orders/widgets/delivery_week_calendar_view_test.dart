import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/widgets/delivery_week_calendar_view.dart';
import 'package:bakery_app/shared/labels/orders.dart';

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

Order _order({
  required int id,
  required String ref,
  required String dueDate,
  required String dueTime,
  String status = 'new',
  String deliveryType = 'door',
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: status,
    deliveryType: deliveryType,
    customerName: 'KH $id',
    items: const [],
    totalPrice: 0,
    dueDate: dueDate,
    dueTime: dueTime,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

Future<Widget> _buildTestApp(List<Order> orders) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // The week grid is horizontally scrollable and at least 130px per
          // day column (NFR4); give the test surface enough width for cards.
          width: 1000,
          child: DeliveryWeekCalendarView(
            orders: orders,
            onRefresh: () async {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders weekday headers and hour labels', (tester) async {
    await tester.pumpWidget(await _buildTestApp(const []));
    await tester.pump();

    for (final header in OrdersLabels.deliveryWeekdayHeaders) {
      expect(find.text(header), findsOneWidget);
    }
    // Hour labels: each appears in both the hour-label column and possibly
    // elsewhere; just verify the first and last are present.
    expect(find.text('6:00'), findsWidgets);
    expect(find.text('21:00'), findsWidgets);
  });

  testWidgets('renders the "Hôm nay" button and week nav arrows', (tester) async {
    await tester.pumpWidget(await _buildTestApp(const []));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryWeekToday), findsOneWidget);
    expect(find.byTooltip(OrdersLabels.deliveryWeekPrevTooltip), findsOneWidget);
    expect(find.byTooltip(OrdersLabels.deliveryWeekNextTooltip), findsOneWidget);
  });

  testWidgets('tapping next/prev shifts the displayed week (AC2)', (tester) async {
    await tester.pumpWidget(await _buildTestApp(const []));
    await tester.pump();

    final now = DateTime.now();
    final thisWeekStart = _dayKey(
      now.subtract(Duration(days: now.weekday - 1)),
    );
    // The current week's first day header date label is shown.
    expect(
      find.textContaining(
        '${now.subtract(Duration(days: now.weekday - 1)).day}/'
        '${now.subtract(Duration(days: now.weekday - 1)).month}',
      ),
      findsWidgets,
    );
    expect(find.text(thisWeekStart), findsNothing); // not rendered as raw

    // Tap next week.
    await tester.tap(find.byTooltip(OrdersLabels.deliveryWeekNextTooltip));
    await tester.pump();
    final nextWeekStart =
        now.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7));
    expect(
      find.textContaining('${nextWeekStart.day}/${nextWeekStart.month}'),
      findsWidgets,
    );

    // Tap prev twice to go back to current week.
    await tester.tap(find.byTooltip(OrdersLabels.deliveryWeekPrevTooltip));
    await tester.pump();
    await tester.tap(find.byTooltip(OrdersLabels.deliveryWeekPrevTooltip));
    await tester.pump();
    final prevWeekStart = now.subtract(Duration(days: now.weekday - 1 + 7));
    expect(
      find.textContaining('${prevWeekStart.day}/${prevWeekStart.month}'),
      findsWidgets,
    );
  });

  testWidgets('tapping "Hôm nay" returns to the current week (AC3)',
      (tester) async {
    await tester.pumpWidget(await _buildTestApp(const []));
    await tester.pump();

    // Jump forward two weeks first.
    await tester.tap(find.byTooltip(OrdersLabels.deliveryWeekNextTooltip));
    await tester.pump();
    await tester.tap(find.byTooltip(OrdersLabels.deliveryWeekNextTooltip));
    await tester.pump();

    // Tap "Hôm nay" — returns to the current week.
    await tester.tap(find.text(OrdersLabels.deliveryWeekToday));
    await tester.pump();

    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    expect(
      find.textContaining('${thisWeekStart.day}/${thisWeekStart.month}'),
      findsWidgets,
    );
  });

  testWidgets('displays order cards in the matching day+hour cell (AC1)',
      (tester) async {
    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    // Use a Monday order at 14:30 → slot "14:00".
    final mondayKey = _dayKey(thisWeekStart);
    final orders = [
      _order(id: 1, ref: 'ORD-1', dueDate: mondayKey, dueTime: '14:30'),
    ];

    await tester.pumpWidget(await _buildTestApp(orders));
    await tester.pump();

    // The mini card customer name should be visible.
    expect(find.text('KH 1'), findsOneWidget);
  });

  testWidgets(
      'unscheduled orders (no dueTime) appear in the "Chưa có giờ" row',
      (tester) async {
    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final mondayKey = _dayKey(thisWeekStart);
    final orders = [
      _order(id: 2, ref: 'ORD-2', dueDate: mondayKey, dueTime: '14:00'),
      Order(
        id: '3',
        orderRef: 'ORD-3',
        status: 'new',
        deliveryType: 'door',
        customerName: 'KH 3',
        items: const [],
        totalPrice: 0,
        dueDate: mondayKey,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];

    await tester.pumpWidget(await _buildTestApp(orders));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryWeekUnscheduled), findsOneWidget);
    expect(find.text('KH 3'), findsOneWidget);
  });
}