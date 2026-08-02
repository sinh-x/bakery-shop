import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/widgets/delivery_content.dart';
import 'package:bakery_app/features/orders/widgets/delivery_week_calendar_components.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/providers/staff_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';

Order _order({
  required int id,
  required String ref,
  required String status,
  String deliveryType = 'pickup',
  String? dueDate,
  String? dueTime,
  double totalPrice = 100000,
  String customerName = 'Test',
  String? assignedStaffId,
}) {
  return Order(
    id: id.toString(),
    orderRef: ref,
    status: status,
    deliveryType: deliveryType,
    isPaid: false,
    customerName: customerName,
    items: const [],
    totalPrice: totalPrice,
    dueDate: dueDate,
    dueTime: dueTime,
    assignedStaffId: assignedStaffId,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );
}

class _FakeOrderListNotifier extends OrderListNotifier {
  final List<Order> orders;
  _FakeOrderListNotifier(this.orders);

  @override
  Future<List<Order>> build() async => orders;

  @override
  Future<void> refresh() async {}
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  final String url;
  _FakeApiBaseUrlNotifier(this.url);

  @override
  String build() => url;
}

class _FakeStaffListNotifier extends StaffListNotifier {
  final List<StaffMember> staff;
  _FakeStaffListNotifier(this.staff);

  @override
  Future<List<StaffMember>> build() async => staff;
}

Widget buildTestWidget(
  List<Order> orders, {
  List<StaffMember>? staff,
  TabController? tabController,
}) {
  return ProviderScope(
    overrides: [
      orderListProvider.overrideWith(
        () => _FakeOrderListNotifier(orders),
      ),
      apiBaseUrlProvider.overrideWith(
        () => _FakeApiBaseUrlNotifier('http://test.local'),
      ),
      if (staff != null)
        staffListProvider.overrideWith(() => _FakeStaffListNotifier(staff)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: DeliveryContent(tabController: tabController),
      ),
    ),
  );
}

/// Switches the delivery view to the list mode. The tab now defaults to the
/// day calendar (FR1/AC1), so tests that assert list-view behavior must
/// toggle there first via the cycle button (day → list).
Future<void> _switchToList(WidgetTester tester) async {
  await tester.tap(find.byTooltip(OrdersLabels.deliverySwitchToList));
  await tester.pumpAndSettle();
}

void main() {
  group('DeliveryContent', () {
    testWidgets('defaults Hôm nay filter selected', (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      // The day calendar is the default view (FR1/AC1); switch to list mode
      // to assert the Today/All filter chips, which only appear in list view.
      await _switchToList(tester);

      final todayChip = find.text(OrdersLabels.deliveryFilterToday);
      expect(todayChip, findsOneWidget);

      final chipWidget = tester.widget<FilterChip>(
        find.ancestor(of: todayChip, matching: find.byType(FilterChip)),
      );
      expect(chipWidget.selected, isTrue);
    });

    testWidgets('shows Hôm nay empty state when only future orders exist',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-FUTURE',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2099-06-15',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });

    testWidgets('shows Tất cả empty state when no delivery orders',
        (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      await tester.tap(find.text(OrdersLabels.deliveryFilterAll));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryEmptyAll), findsOneWidget);
    });

    testWidgets('toggling to Tất cả shows future-dated orders',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-FUTURE',
          status: 'new',
          deliveryType: 'door',
          dueDate: '2099-06-15',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);

      await tester.tap(find.text(OrdersLabels.deliveryFilterAll));
      await tester.pumpAndSettle();

      expect(find.text('ORD-FUTURE'), findsOneWidget);
    });

    testWidgets('renders today delivery order cards', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-TODAY',
          status: 'ready',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
          customerName: 'Nguyen Van A',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text('ORD-TODAY'), findsOneWidget);
      expect(find.text('Nguyen Van A'), findsOneWidget);
    });

    testWidgets('groups orders by status with both visible', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-NEW',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
        ),
        _order(
          id: 2,
          ref: 'ORD-READY',
          status: 'ready',
          deliveryType: 'door',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text('ORD-NEW'), findsOneWidget);
      expect(find.text('ORD-READY'), findsOneWidget);
    });

    testWidgets('shows overdue orders in Hôm nay view', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-OVERDUE',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-01',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text('ORD-OVERDUE'), findsOneWidget);
    });

    testWidgets('shows unscheduled orders in Hôm nay view', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-NO-DATE',
          status: 'confirmed',
          deliveryType: 'door',
          dueDate: null,
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text('ORD-NO-DATE'), findsOneWidget);
    });

    testWidgets('non-delivery orders excluded from Hôm nay', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-PICKUP',
          status: 'new',
          deliveryType: 'pickup',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });

    testWidgets('terminal status orders excluded from delivery',
        (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-COMPLETE',
          status: 'completed',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      expect(find.text(OrdersLabels.deliveryEmptyToday), findsOneWidget);
    });

    testWidgets('AC9: toggling to calendar and back to list preserves '
        'status-grouped list rendering', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-NEW',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
        ),
        _order(
          id: 2,
          ref: 'ORD-READY',
          status: 'ready',
          deliveryType: 'door',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      // Default is the day calendar (FR1/AC1); switch to list mode first.
      await _switchToList(tester);

      // Default list view renders both orders grouped by status.
      expect(find.text('ORD-NEW'), findsOneWidget);
      expect(find.text('ORD-READY'), findsOneWidget);

      // Toggle to week calendar view (list → week).
      await tester.tap(find.byTooltip(OrdersLabels.deliverySwitchToWeek));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryContent), findsOneWidget);

      // Toggle to day view then back to list — the status-grouped list
      // still renders.
      await tester.tap(find.byTooltip(OrdersLabels.deliverySwitchToDay));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(OrdersLabels.deliverySwitchToList));
      await tester.pumpAndSettle();

      expect(find.text('ORD-NEW'), findsOneWidget);
      expect(find.text('ORD-READY'), findsOneWidget);
    });

    testWidgets('AC1: defaults to the day calendar view on open',
        (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      // The day calendar is the default: its "Hôm nay" TextButton is
      // present, and the list view's Today/All FilterChips are absent.
      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.text(OrdersLabels.deliveryDayToday),
        ),
        findsOneWidget,
      );
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('AC4: day view defaults to today when no non-terminal '
        'delivery orders exist', (tester) async {
      await tester.pumpWidget(buildTestWidget([]));
      await tester.pumpAndSettle();

      // The "Hôm nay" button is disabled when already on today.
      final todayButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(OrdersLabels.deliveryDayToday),
          matching: find.byType(TextButton),
        ),
      );
      expect(todayButton.onPressed, isNull);
    });

    testWidgets('AC3/FR4: day view defaults to today even when next due '
        'order is in the future', (tester) async {
      final orders = [
        _order(
          id: 1,
          ref: 'ORD-DUE',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2099-06-15',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(orders));
      await tester.pumpAndSettle();

      // Per FR4/AC3 the day calendar always defaults to today (not the
      // next due date). The "Hôm nay" button must be disabled (already
      // on today) and the day nav label shows today — NOT 2099-06-15.
      final todayButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(OrdersLabels.deliveryDayToday),
          matching: find.byType(TextButton),
        ),
      );
      expect(todayButton.onPressed, isNull);
      expect(
        find.text(OrdersLabels.deliveryDayLabel(DateTime.now())),
        findsOneWidget,
      );
      expect(
        find.text(OrdersLabels.deliveryDayLabel(DateTime(2099, 6, 15))),
        findsNothing,
      );
    });

    testWidgets('AC3/FR4: current-time line widget is present on the day '
        'calendar (visible when current time is in the 6:00–21:00 range)',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(const []));
      await tester.pumpAndSettle();

      // The day calendar is the default view and always constructs a
      // CurrentTimeLine. The line's `visible` flag is true only when the
      // focused day is today AND the current time is within the 6:00–21:00
      // grid range (currentTimeGridOffset() != null). Since the day calendar
      // now defaults to today (FR4/AC3), the time line is visible whenever
      // the current time is in range — satisfying AC3.
      expect(find.byType(CurrentTimeLine), findsOneWidget);
    });

    // ── DG-304 Phase 4: staff filter + workload summary ──────────────

    final deliveryStaff = [
      StaffMember(id: 10, name: 'An', role: 'giao-hang', active: true),
      StaffMember(id: 20, name: 'Binh', role: 'giao-hang', active: true),
      // Non-delivery role staff are now included (DG-329 Phase 1 / FR2 —
      // all active staff appear in the dropdown regardless of role).
      StaffMember(id: 30, name: 'Ca', role: 'thu-ngan', active: true),
      // Inactive staff should still be excluded.
      StaffMember(id: 40, name: 'Dung', role: 'giao-hang', active: false),
    ];

    final todayOrders = [
      _order(
        id: 1,
        ref: 'ORD-AN',
        status: 'new',
        deliveryType: 'bus',
        dueDate: '2026-07-19',
        assignedStaffId: '10',
      ),
      _order(
        id: 2,
        ref: 'ORD-BINH',
        status: 'ready',
        deliveryType: 'door',
        dueDate: '2026-07-19',
        assignedStaffId: '20',
      ),
      _order(
        id: 3,
        ref: 'ORD-UNASSIGNED',
        status: 'new',
        deliveryType: 'bus',
        dueDate: '2026-07-19',
      ),
    ];

    testWidgets('FR2/FR4: staff filter dropdown includes All + all active '
        'staff (excludes inactive)', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: deliveryStaff,
      ));
      await tester.pumpAndSettle();

      // Open the staff filter dropdown.
      await tester.tap(find.text(OrdersLabels.staffFilterAll));
      await tester.pumpAndSettle();

      // "All" appears as both the selected hint and a menu item; all
      // active staff appear as menu items only.
      expect(find.text('An'), findsOneWidget);
      expect(find.text('Binh'), findsOneWidget);
      // Non-delivery role but active staff are now included (DG-329
      // Phase 1 / FR2).
      expect(find.text('Ca'), findsOneWidget);
      // Inactive staff remain excluded.
      expect(find.text('Dung'), findsNothing);
    });

    testWidgets('AC1/FR3: selecting a staff shows only their orders',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: deliveryStaff,
      ));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      // Initially all three orders are visible.
      expect(find.text('ORD-AN'), findsOneWidget);
      expect(find.text('ORD-BINH'), findsOneWidget);
      expect(find.text('ORD-UNASSIGNED'), findsOneWidget);

      // Open the staff filter dropdown and select "An".
      await tester.tap(find.text(OrdersLabels.staffFilterAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text('An').last);
      await tester.pumpAndSettle();

      expect(find.text('ORD-AN'), findsOneWidget);
      expect(find.text('ORD-BINH'), findsNothing);
      expect(find.text('ORD-UNASSIGNED'), findsNothing);
    });

    testWidgets('AC2: "All" option shows all delivery orders regardless of '
        'assignment', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: deliveryStaff,
      ));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      // Filter to one staff, then back to "All".
      await tester.tap(find.text(OrdersLabels.staffFilterAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text('An').last);
      await tester.pumpAndSettle();
      expect(find.text('ORD-BINH'), findsNothing);

      await tester.tap(find.text('An'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(OrdersLabels.staffFilterAll));
      await tester.pumpAndSettle();

      expect(find.text('ORD-AN'), findsOneWidget);
      expect(find.text('ORD-BINH'), findsOneWidget);
      expect(find.text('ORD-UNASSIGNED'), findsOneWidget);
    });

    testWidgets('AC3/FR5: workload summary shows per-staff counts for today',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: deliveryStaff,
      ));
      await tester.pumpAndSettle();

      // The workload summary renders in the default day calendar view too.
      expect(find.text(OrdersLabels.workloadSummaryTitle), findsOneWidget);
      expect(
        find.text(OrdersLabels.workloadStaffCount('An', 1)),
        findsOneWidget,
      );
      expect(
        find.text(OrdersLabels.workloadStaffCount('Binh', 1)),
        findsOneWidget,
      );
      // Non-delivery role but active staff now also appear in the summary
      // with a zero count (DG-329 Phase 1 / FR6).
      expect(
        find.text(OrdersLabels.workloadStaffCount('Ca', 0)),
        findsOneWidget,
      );
      expect(
        find.text('${OrdersLabels.workloadUnassigned}: 1'),
        findsOneWidget,
      );
    });

    testWidgets('AC5/FR6: workload summary shows for all active staff even '
        'when no giao-hang role staff exist', (tester) async {
      // Reproduces the original bug: previously the summary was hidden when
      // no `giao-hang`-role staff existed. After DG-329 Phase 1 + Phase 5,
      // `_deliveryStaff` returns ALL active staff, so the summary renders
      // whenever any active staff exist (regardless of role).
      final nonDeliveryOnlyStaff = [
        StaffMember(id: 30, name: 'Ca', role: 'thu-ngan', active: true),
        StaffMember(id: 50, name: 'Em', role: 'ban-hang', active: true),
        // Inactive staff excluded.
        StaffMember(id: 40, name: 'Dung', role: 'giao-hang', active: false),
      ];
      final todayOrdersNoGiaoHang = [
        _order(
          id: 1,
          ref: 'ORD-CA',
          status: 'new',
          deliveryType: 'bus',
          dueDate: '2026-07-19',
          assignedStaffId: '30',
        ),
        _order(
          id: 2,
          ref: 'ORD-UNASSIGNED',
          status: 'ready',
          deliveryType: 'door',
          dueDate: '2026-07-19',
        ),
      ];
      await tester.pumpWidget(buildTestWidget(
        todayOrdersNoGiaoHang,
        staff: nonDeliveryOnlyStaff,
      ));
      await tester.pumpAndSettle();

      // The summary title is present (NOT hidden) even though no active
      // `giao-hang`-role staff exist — this is the AC5 regression guard.
      expect(find.text(OrdersLabels.workloadSummaryTitle), findsOneWidget);
      // Active non-delivery-role staff appear with their counts.
      expect(
        find.text(OrdersLabels.workloadStaffCount('Ca', 1)),
        findsOneWidget,
      );
      expect(
        find.text(OrdersLabels.workloadStaffCount('Em', 0)),
        findsOneWidget,
      );
      // Inactive `giao-hang` staff (Dung) is excluded.
      expect(find.text('Dung'), findsNothing);
      // Unassigned bucket reflects the one unassigned order.
      expect(
        find.text('${OrdersLabels.workloadUnassigned}: 1'),
        findsOneWidget,
      );
    });

    testWidgets('AC5/FR6: workload summary hides when no active staff exist',
        (tester) async {
      final allInactiveStaff = [
        StaffMember(id: 40, name: 'Dung', role: 'giao-hang', active: false),
      ];
      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: allInactiveStaff,
      ));
      await tester.pumpAndSettle();

      // No active staff → `_deliveryStaff` is empty → summary hides entirely
      // (no title, no chips).
      expect(find.text(OrdersLabels.workloadSummaryTitle), findsNothing);
      expect(find.text(OrdersLabels.workloadSummaryEmpty), findsNothing);
    });

    testWidgets('AC7: staff filter resets to "All" on tab leave',
        (tester) async {
      final tabController = TabController(length: 3, vsync: tester);
      // Start on the delivery tab (index 2) so the staff filter persists
      // until the user navigates away (AC7).
      tabController.index = 2;
      addTearDown(tabController.dispose);

      await tester.pumpWidget(buildTestWidget(
        todayOrders,
        staff: deliveryStaff,
        tabController: tabController,
      ));
      await tester.pumpAndSettle();

      await _switchToList(tester);

      // Select "An" — only their orders show.
      await tester.tap(find.text(OrdersLabels.staffFilterAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text('An').last);
      await tester.pumpAndSettle();
      expect(find.text('ORD-BINH'), findsNothing);

      // Navigate away from the delivery tab (index 2 → 0) and pump a frame
      // so the build-time reset guard fires.
      tabController.index = 0;
      await tester.pumpAndSettle();

      // Navigate back to the delivery tab.
      tabController.index = 2;
      await tester.pumpAndSettle();

      // The filter has reset to "All" — all three orders visible again.
      expect(find.text('ORD-AN'), findsOneWidget);
      expect(find.text('ORD-BINH'), findsOneWidget);
      expect(find.text('ORD-UNASSIGNED'), findsOneWidget);
    });
  });
}
