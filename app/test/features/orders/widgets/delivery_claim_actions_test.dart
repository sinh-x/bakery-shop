import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/providers/delivery_claim_providers.dart';
import 'package:bakery_app/features/orders/widgets/delivery_claim_actions.dart';
import 'package:bakery_app/features/orders/widgets/delivery_order_card.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';

const _testRef = 'TEST-DELIVERY-1';

class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  _FakeOrderPhotosNotifier() : super(_testRef);

  @override
  Future<List<OrderPhoto>> build() async => const [];
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
  CurrentStaff staff,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentStaffProvider.overrideWith((ref) async => staff),
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

  // AC9: non-delivery staff does not see the claim button.
  testWidgets('AC9: non giao-hang staff does not see claim button',
      (tester) async {
    await tester.pumpWidget(await _buildApp(_deliveryOrder(), _nonDeliveryStaff()));
    await tester.pump();

    expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
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
    Widget standalone(Order order, CurrentStaff staff) => ProviderScope(
          overrides: [currentStaffProvider.overrideWith((ref) async => staff)],
          child: MaterialApp(
            home: Scaffold(
              body: DeliveryClaimActions(order: order),
            ),
          ),
        );

    testWidgets('renders nothing for non-delivery staff', (tester) async {
      await tester.pumpWidget(
        standalone(_deliveryOrder(), _nonDeliveryStaff()),
      );
      await tester.pump();

      expect(find.byType(DeliveryClaimActions), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
      expect(find.text(OrdersLabels.deliveryUnassigned), findsNothing);
    });
  });
}