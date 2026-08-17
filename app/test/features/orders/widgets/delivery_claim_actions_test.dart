import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/providers/delivery_claim_providers.dart';
import 'package:bakery_app/features/orders/widgets/delivery_claim_actions.dart';
import 'package:bakery_app/features/orders/widgets/delivery_order_card.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/data/providers/staff_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';

const _testRef = 'TEST-DELIVERY-1';

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  _FakeOrderPhotosNotifier() : super(_testRef);

  @override
  Future<List<OrderPhoto>> build() async => const [];
}

/// Fake [StaffListNotifier] returning a fixed staff list so
/// [DeliveryClaimActions] can resolve the assigned staff name without hitting
/// the network (DG-329 Phase 2). The existing card tests pass the backend-
/// provided `assignedStaffName`, so an empty list suffices — the helper
/// returns the backend name as-is.
class _FakeStaffListNotifier extends StaffListNotifier {
  final List<StaffMember> staff;
  _FakeStaffListNotifier(this.staff);

  @override
  Future<List<StaffMember>> build() async => staff;
}

Order _deliveryOrder({
  String status = 'new',
  String? assignedStaffId,
  String assignedStaffName = '',
}) {
  return Order(
    id: '1',
    orderRef: _testRef,
    customerName: 'Nguyễn Giao A',
    items: const [],
    totalPrice: 150000.0,
    status: status,
    deliveryType: 'door',
    dueDate: '2026-07-30',
    dueTime: '10:00',
    assignedStaffId: assignedStaffId,
    assignedStaffName: assignedStaffName,
    createdAt: DateTime(2026, 7, 28),
    updatedAt: DateTime(2026, 7, 28),
  );
}

CurrentStaff _giaoHangStaff({int staffId = 7}) => CurrentStaff(
      staffId: staffId,
      staffName: 'Người Giao A',
      role: 'giao-hang',
      isAdmin: false,
    );

CurrentStaff _nonDeliveryStaff() => const CurrentStaff(
      staffId: 9,
      staffName: 'Thu Ngân',
      role: 'thu-ngan',
      isAdmin: false,
    );

CurrentStaff _adminStaff() => const CurrentStaff(
      staffId: 1,
      staffName: 'Admin',
      role: 'admin',
      isAdmin: true,
    );

Future<Widget> _buildApp(
  Order order,
  CurrentStaff staff, {
  List<StaffMember>? staffList,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentStaffProvider.overrideWith((ref) async => staff),
      staffListProvider.overrideWith(() => _FakeStaffListNotifier(staffList ?? const [])),
      orderPhotosProvider(order.orderRef)
          .overrideWith(_FakeOrderPhotosNotifier.new),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: DeliveryOrderCard(order: order, onTap: () {}),
        ),
      ),
    ),
  );
}

/// Fake [OrderService] for snackbar tests — resolves claim/unclaim/detail/list
/// without hitting the network. `failAssign`/`failUnclaim` simulate API errors.
class _FakeClaimOrderService extends OrderService {
  _FakeClaimOrderService(
    this.base, {
    this.failAssign = false,
    this.failUnclaim = false,
  }) : super(Dio(BaseOptions(baseUrl: 'http://test')));

  final Order base;
  final bool failAssign;
  final bool failUnclaim;

  @override
  Future<Order> assignOrder(String ref) async {
    if (failAssign) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/orders/$ref/assign'),
      );
    }
    return base.copyWith(assignedStaffId: '7', assignedStaffName: 'Người Giao A');
  }

  @override
  Future<Order> unassignOrder(String ref) async {
    if (failUnclaim) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/orders/$ref/unassign'),
      );
    }
    return base.copyWith(assignedStaffId: null, assignedStaffName: '');
  }

  @override
  Future<Order> getOrder(String ref) async => base;

  @override
  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async => [base];
}

Future<Widget> _buildSnackbarApp(
  Order order,
  CurrentStaff staff, {
  bool failAssign = false,
  bool failUnclaim = false,
  List<StaffMember>? staffList,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final service = _FakeClaimOrderService(
    order,
    failAssign: failAssign,
    failUnclaim: failUnclaim,
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentStaffProvider.overrideWith((ref) async => staff),
      staffListProvider.overrideWith(() => _FakeStaffListNotifier(staffList ?? const [])),
      orderServiceProvider.overrideWithValue(service),
      orderPhotosProvider(order.orderRef)
          .overrideWith(_FakeOrderPhotosNotifier.new),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: DeliveryOrderCard(order: order, onTap: () {}),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // AC6/FR5: giao-hang staff sees a claim button on an unclaimed non-terminal
  // order.
  testWidgets('AC6: giao-hang staff sees claim button on unclaimed order',
      (tester) async {
    await tester.pumpWidget(await _buildApp(_deliveryOrder(), _giaoHangStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
  });

  // DG-329 Phase 6 / FR8 / AC7: delivery order cards in the list view show a
  // claim button when the order is unassigned (regression guard for the card
  // claim button — DeliveryClaimActions already renders on the card; this
  // test pins the behavior so future repositioning cannot regress it).
  testWidgets(
      'AC7: delivery order card shows claim button when unassigned '
      '(list-view regression)', (tester) async {
    await tester.pumpWidget(await _buildApp(_deliveryOrder(), _giaoHangStaff()));
    await tester.pump();

    expect(find.byType(DeliveryOrderCard), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryUnassigned), findsOneWidget);
  });

  testWidgets(
      'AC7: delivery order card shows no claim button when assigned to '
      'another staff (non-admin)', (tester) async {
    final order = _deliveryOrder(
      assignedStaffId: '7',
      assignedStaffName: 'Người Giao A',
    );
    await tester.pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 8)));
    await tester.pump();

    expect(find.byType(DeliveryOrderCard), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
  });

  // AC9: any linked staff sees the claim button.
  testWidgets('AC9: any linked staff sees claim button',
      (tester) async {
    await tester.pumpWidget(await _buildApp(_deliveryOrder(), _nonDeliveryStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
  });

  // AC7: assigned staff name is visible on the order card.
  testWidgets('AC7: assigned staff name is displayed on order card',
      (tester) async {
    final order = _deliveryOrder(
      assignedStaffId: '7',
      assignedStaffName: 'Người Giao A',
    );
    await tester.pumpWidget(await _buildApp(order, _giaoHangStaff()));
    await tester.pump();

    expect(
      find.textContaining('Người Giao A'),
      findsOneWidget,
    );
    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
  });

  // AC8: the assigned staff sees an unclaim button.
  testWidgets('AC8: assigned staff sees unclaim button', (tester) async {
    final order = _deliveryOrder(
      assignedStaffId: '7',
      assignedStaffName: 'Người Giao A',
    );
    await tester.pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 7)));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
  });

  // AC10 (client side): another staff cannot unclaim someone else's order.
  testWidgets('AC10: other giao-hang staff cannot unclaim another\'s order',
      (tester) async {
    final order = _deliveryOrder(
      assignedStaffId: '7',
      assignedStaffName: 'Người Giao A',
    );
    await tester.pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 8)));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
  });

  // Admin can unclaim any claimed order.
  testWidgets('admin can unclaim any claimed order', (tester) async {
    final order = _deliveryOrder(
      assignedStaffId: '7',
      assignedStaffName: 'Người Giao A',
    );
    await tester.pumpWidget(await _buildApp(order, _adminStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsOneWidget);
  });

  // Terminal orders show no claim/unclaim buttons.
  testWidgets('terminal order shows no claim buttons', (tester) async {
    final order = _deliveryOrder(status: 'cancelled');
    await tester.pumpWidget(await _buildApp(order, _giaoHangStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
    expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
  });

  // Unassigned indicator shows for eligible staff on unclaimed orders.
  testWidgets(
      'unassigned indicator shows for eligible staff on unclaimed order',
      (tester) async {
    await tester.pumpWidget(await _buildApp(_deliveryOrder(), _giaoHangStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryUnassigned), findsOneWidget);
  });

  group('DeliveryClaimActions (standalone)', () {
    Widget standalone(
      Order order,
      CurrentStaff staff, {
      List<StaffMember>? staffList,
    }) =>
        ProviderScope(
          overrides: [
            currentStaffProvider.overrideWith((ref) async => staff),
            staffListProvider.overrideWith(
              () => _FakeStaffListNotifier(staffList ?? const []),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DeliveryClaimActions(order: order),
            ),
          ),
        );

    testWidgets('renders claim button for any linked staff', (tester) async {
      await tester.pumpWidget(
        standalone(_deliveryOrder(), _nonDeliveryStaff()),
      );
      await tester.pump();

      expect(find.byType(DeliveryClaimActions), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryUnassigned), findsOneWidget);
    });

    // DG-329 Phase 2 / FR3 / AC2: assigned staff name displays the real name
    // (not "NV #<id> (đã ngưng)").
    testWidgets('AC2: displays the real assigned staff name', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(standalone(order, _giaoHangStaff()));
      await tester.pump();

      expect(find.textContaining('Người Giao A'), findsOneWidget);
    });

    // DG-329 Phase 2 / FR3 / AC2: when the staff record is missing entirely
    // (deleted), the "NV #<id>" fallback is shown — never the misleading
    // "NV #<id> (đã ngưng)" combo.
    testWidgets('AC2: missing staff record shows "NV #<id>" fallback',
        (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '42',
        assignedStaffName: '',
      );
      await tester.pumpWidget(standalone(order, _giaoHangStaff()));
      await tester.pump();

      expect(find.textContaining('NV #42'), findsOneWidget);
      expect(find.textContaining('đã ngưng'), findsNothing);
    });
  });

  group('DeliveryClaimActions snackbar feedback (Phase 1 — AC6)', () {
    testWidgets('claim success shows success snackbar', (tester) async {
      await tester
          .pumpWidget(await _buildSnackbarApp(_deliveryOrder(), _giaoHangStaff()));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryClaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryClaimSuccess), findsOneWidget);
    });

    testWidgets('unclaim success shows success snackbar', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester
          .pumpWidget(await _buildSnackbarApp(order, _giaoHangStaff(staffId: 7)));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryUnclaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryUnclaimSuccess), findsOneWidget);
    });

    testWidgets('claim failure shows error snackbar', (tester) async {
      await tester.pumpWidget(await _buildSnackbarApp(
        _deliveryOrder(),
        _giaoHangStaff(),
        failAssign: true,
      ));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryClaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryClaimFailed), findsOneWidget);
    });
  });
}