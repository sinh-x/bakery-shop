import 'dart:async';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/features/orders/providers/delivery_claim_handler.dart';
import 'package:bakery_app/features/orders/providers/delivery_claim_providers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testRef = 'TEST-HANDLER-1';

Order _deliveryOrder({
  String? assignedStaffId,
  String assignedStaffName = '',
}) {
  return Order(
    id: '1',
    orderRef: _testRef,
    customerName: 'Nguyễn Giao A',
    items: const [],
    totalPrice: 150000.0,
    status: 'new',
    deliveryType: 'door',
    dueDate: '2026-07-30',
    dueTime: '10:00',
    assignedStaffId: assignedStaffId,
    assignedStaffName: assignedStaffName,
    createdAt: DateTime(2026, 7, 28),
    updatedAt: DateTime(2026, 7, 28),
  );
}

/// Fake [OrderService] resolving claim/unclaim without network. `failAssign`
/// / `failUnclaim` simulate API errors.
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

/// Harness that pumps a [ProviderScope] with the fake [OrderService] and a
/// [Consumer] that exposes its mounted [BuildContext] + [WidgetRef] to the
/// test via [completer]. This lets tests call [handleDeliveryClaimAction]
/// with a real, mounted [WidgetRef] (as the production callers do).
class _Harness {
  _Harness(this.order, {this.failAssign = false, this.failUnclaim = false});

  final Order order;
  final bool failAssign;
  final bool failUnclaim;
  final Completer<({BuildContext context, WidgetRef ref})> ready =
      Completer<({BuildContext context, WidgetRef ref})>();

  Future<Widget> build() async {
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
        orderServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              if (!ready.isCompleted) {
                ready.complete((context: context, ref: ref));
              }
              return const SizedBox(width: 10, height: 10);
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // These tests verify the single shared claim/unclaim code path
  // (DG-311 Phase 4 / FR5 / AC7): handleDeliveryClaimAction routes to
  // OrderClaimNotifier.claim()/unclaim() and shows the correct top-anchored
  // snackbar for each of the four outcomes (claim success/failure,
  // unclaim success/failure). All three consumers (DeliveryClaimActions,
  // DeliveryClaimInlineActions, order detail context menu) delegate here.

  testWidgets('claim success shows claim success snackbar', (tester) async {
    final harness = _Harness(_deliveryOrder());
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: true);
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.deliveryClaimSuccess), findsOneWidget);
  });

  testWidgets('unclaim success shows unclaim success snackbar', (tester) async {
    final harness = _Harness(_deliveryOrder(assignedStaffId: '7'));
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: false);
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.deliveryUnclaimSuccess), findsOneWidget);
  });

  testWidgets('claim failure shows claim error snackbar', (tester) async {
    final harness = _Harness(_deliveryOrder(), failAssign: true);
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: true);
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.deliveryClaimFailed), findsOneWidget);
  });

  testWidgets('unclaim failure shows unclaim error snackbar', (tester) async {
    final harness = _Harness(_deliveryOrder(assignedStaffId: '7'),
        failUnclaim: true);
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: false);
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.deliveryUnclaimFailed), findsOneWidget);
  });

  // AC7: the shared helper is the single entry point — it routes to
  // OrderClaimNotifier.claim() when isClaim and unclaim() otherwise.
  testWidgets('isClaim=true routes to OrderClaimNotifier.claim()',
      (tester) async {
    final harness = _Harness(_deliveryOrder());
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: true);
    await tester.pumpAndSettle();

    final state = ctx.ref.read(orderClaimProvider);
    expect(state.value?.isAssigned, isTrue);
    expect(state.value?.assignedStaffName, 'Người Giao A');
  });

  testWidgets('isClaim=false routes to OrderClaimNotifier.unclaim()',
      (tester) async {
    final harness = _Harness(_deliveryOrder(assignedStaffId: '7'));
    await tester.pumpWidget(await harness.build());
    final ctx = await harness.ready.future;

    await handleDeliveryClaimAction(ctx.context, ctx.ref, _testRef,
        isClaim: false);
    await tester.pumpAndSettle();

    final state = ctx.ref.read(orderClaimProvider);
    expect(state.value?.isAssigned, isFalse);
    expect(state.value?.assignedStaffName, '');
  });
}