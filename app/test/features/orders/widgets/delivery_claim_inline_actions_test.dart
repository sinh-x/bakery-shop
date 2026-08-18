import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/providers/delivery_claim_providers.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/delivery_claim_inline_actions.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_info_block.dart';
import 'package:bakery_app/data/providers/staff_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';

const _testRef = 'TEST-INLINE-1';

Order _deliveryOrder({
  String status = 'new',
  String deliveryType = 'door',
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
    deliveryType: deliveryType,
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

CurrentStaff _adminStaff() => const CurrentStaff(
      staffId: 1,
      staffName: 'Admin',
      role: 'admin',
      isAdmin: true,
    );

/// Fake [OrderService] for snackbar tests — resolves claim/unclaim without
/// hitting the network. `failAssign`/`failUnclaim` simulate API errors.
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
}

Future<Widget> _buildApp(
  Order order,
  CurrentStaff staff, {
  bool failAssign = false,
  bool failUnclaim = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final service = _FakeClaimOrderService(
    order,
    failAssign: failAssign,
    failUnclaim: failUnclaim,
  );
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(
      _InlineInterceptor(service: service, base: order),
    );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentStaffProvider.overrideWith((ref) async => staff),
      orderServiceProvider.overrideWithValue(service),
      dioProvider.overrideWithValue(dio),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: DeliveryClaimInlineActions(order: order),
        ),
      ),
    ),
  );
}

/// Fake [StaffListNotifier] returning a fixed staff list so [OrderInfoBlock]
/// can resolve the assigned staff name without hitting the network
/// (DG-329 Phase 6 / FR7 / AC6).
class _FakeStaffListNotifier extends StaffListNotifier {
  final List<StaffMember> staff;
  _FakeStaffListNotifier(this.staff);

  @override
  Future<List<StaffMember>> build() async => staff;
}

class _InlineInterceptor extends Interceptor {
  _InlineInterceptor({required this.service, required this.base});

  final OrderService service;
  final Order base;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders/$_testRef') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': base.id,
            'orderRef': base.orderRef,
            'customerName': base.customerName,
            'items': const <dynamic>[],
            'totalPrice': base.totalPrice,
            'status': base.status,
            'deliveryType': base.deliveryType,
            'createdAt': '2026-07-28T08:00:00Z',
            'updatedAt': '2026-07-28T08:00:00Z',
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DeliveryClaimInlineActions visibility (FR4/AC5)', () {
    testWidgets('giao-hang staff sees claim button on unclaimed delivery order',
        (tester) async {
      await tester.pumpWidget(await _buildApp(_deliveryOrder(), _giaoHangStaff()));
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
    });

    testWidgets('assigned staff sees unclaim button', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 7)));
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
    });

    testWidgets('admin can unclaim any claimed order', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(await _buildApp(order, _adminStaff()));
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsOneWidget);
    });

    testWidgets('other giao-hang staff cannot unclaim someone else\'s order',
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

    testWidgets('terminal order shows no inline buttons', (tester) async {
      await tester.pumpWidget(
        await _buildApp(_deliveryOrder(status: 'cancelled'), _giaoHangStaff()),
      );
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
    });

    testWidgets('non-delivery order shows no inline buttons', (tester) async {
      await tester.pumpWidget(
        await _buildApp(
          _deliveryOrder(deliveryType: 'pickup'),
          _giaoHangStaff(),
        ),
      );
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
    });

    testWidgets(
        'already-claimed-by-another delivery order shows no claim button '
        'for a non-admin staff', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 8)));
      await tester.pump();

      // Already claimed by someone else + non-admin → neither button shows.
      expect(find.byType(DeliveryClaimInlineActions), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsNothing);
    });
  });

  group('DeliveryClaimInlineActions snackbar feedback (Phase 3)', () {
    testWidgets('claim success shows success snackbar', (tester) async {
      await tester
          .pumpWidget(await _buildApp(_deliveryOrder(), _giaoHangStaff()));
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
          .pumpWidget(await _buildApp(order, _giaoHangStaff(staffId: 7)));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryUnclaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryUnclaimSuccess), findsOneWidget);
    });

    testWidgets('claim failure shows error snackbar', (tester) async {
      await tester.pumpWidget(await _buildApp(
        _deliveryOrder(),
        _giaoHangStaff(),
        failAssign: true,
      ));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryClaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryClaimFailed), findsOneWidget);
    });

    testWidgets('unclaim failure shows error snackbar', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(await _buildApp(
        order,
        _giaoHangStaff(staffId: 7),
        failUnclaim: true,
      ));
      await tester.pump();

      await tester.tap(find.text(OrdersLabels.deliveryUnclaimButton));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.deliveryUnclaimFailed), findsOneWidget);
    });
  });

  // DG-329 Phase 6 / FR7 / AC6: the claim/unclaim button must render directly
  // below the "Nhân viên giao hàng" assignment row, inside OrderInfoBlock —
  // not below the entire OrderInfoBlock as a sibling. This group verifies the
  // repositioned layout by rendering OrderInfoBlock (which now owns
  // DeliveryClaimInlineActions) and asserting the claim button appears after
  // the assignment label in widget tree order.
  group('DeliveryClaimInlineActions repositioned inside OrderInfoBlock (FR7/AC6)', () {
    Future<Widget> buildInfoBlockApp(
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
          staffListProvider.overrideWith(() =>
              _FakeStaffListNotifier(staffList ?? const [])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: OrderInfoBlock(
                order: order,
                formatDueDisplay: (a, b) => '',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
        'AC6: claim button renders inside OrderInfoBlock directly below '
        'the "Nhân viên giao hàng" assignment row for an unassigned order',
        (tester) async {
      await tester.pumpWidget(
        await buildInfoBlockApp(_deliveryOrder(), _giaoHangStaff()),
      );
      await tester.pump();

      // The assignment label "Nhân viên giao hàng" is present.
      expect(find.text(OrdersLabels.deliveryAssignee), findsOneWidget);
      // The claim button is present (repositioned inside OrderInfoBlock).
      expect(find.text(OrdersLabels.deliveryClaimButton), findsOneWidget);

      // Tree-order assertion: the claim button is a descendant of
      // OrderInfoBlock (i.e. repositioned inside the block, not a sibling),
      // and the button paints below the assignment label.
      final infoBlockFinder = find.byType(OrderInfoBlock);
      final labelFinder = find.text(OrdersLabels.deliveryAssignee);
      final buttonFinder = find.text(OrdersLabels.deliveryClaimButton);
      expect(
        find.descendant(of: infoBlockFinder, matching: labelFinder),
        findsOneWidget,
      );
      expect(
        find.descendant(of: infoBlockFinder, matching: buttonFinder),
        findsOneWidget,
      );
      final labelRect = tester.getTopLeft(labelFinder);
      final buttonRect = tester.getTopLeft(buttonFinder);
      expect(buttonRect.dy, greaterThan(labelRect.dy),
          reason: 'claim button should render below the assignment label');
    });

    testWidgets(
        'AC6: unclaim button renders inside OrderInfoBlock directly below '
        'the "Nhân viên giao hàng" assignment row for an assigned order '
        '(assigned staff)', (tester) async {
      final order = _deliveryOrder(
        assignedStaffId: '7',
        assignedStaffName: 'Người Giao A',
      );
      await tester.pumpWidget(
        await buildInfoBlockApp(order, _giaoHangStaff(staffId: 7)),
      );
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryAssignee), findsOneWidget);
      expect(find.text(OrdersLabels.deliveryUnclaimButton), findsOneWidget);

      final labelRect = tester.getTopLeft(find.text(OrdersLabels.deliveryAssignee));
      final buttonRect = tester.getTopLeft(
          find.text(OrdersLabels.deliveryUnclaimButton));
      expect(buttonRect.dy, greaterThan(labelRect.dy),
          reason: 'unclaim button should render below the assignment label');
    });

    testWidgets(
        'AC6: non-delivery order renders no claim button inside '
        'OrderInfoBlock', (tester) async {
      await tester.pumpWidget(
        await buildInfoBlockApp(
          _deliveryOrder(deliveryType: 'pickup'),
          _giaoHangStaff(),
        ),
      );
      await tester.pump();

      expect(find.text(OrdersLabels.deliveryAssignee), findsNothing);
      expect(find.text(OrdersLabels.deliveryClaimButton), findsNothing);
    });
  });
}