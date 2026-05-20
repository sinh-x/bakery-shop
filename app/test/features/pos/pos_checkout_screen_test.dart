import 'dart:async';

import 'package:bakery_app/features/pos/pos_checkout_screen.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/product.dart';

class _SeededPosCartNotifier extends PosCartNotifier {
  _SeededPosCartNotifier(this._items);

  final List<PosCartItem> _items;

  @override
  PosCartState build() => PosCartState(items: _items);
}

class _FakeOrderService extends OrderService {
  _FakeOrderService({this.createOrderCompleter}) : super(Dio());

  final List<String?> paymentMethods = <String?>[];
  final Completer<Order>? createOrderCompleter;
  int createOrderCallCount = 0;

  @override
  Future<Order> createOrder({
    required String customerName,
    String customerPhone = '',
    List<Map<String, dynamic>> items = const [],
    String? dueDate,
    String? dueTime,
    String deliveryType = 'pickup',
    String deliveryAddress = '',
    String notes = '',
    String? source,
    String createdBy = '',
    double shippingFee = 0.0,
    String? status,
    String? paymentMethod,
  }) async {
    createOrderCallCount += 1;
    paymentMethods.add(paymentMethod);
    if (createOrderCompleter != null) {
      return createOrderCompleter!.future;
    }
    return Order(
      id: '1',
      orderRef: 'ORD-001',
      customerName: customerName,
      items: const [],
      totalPrice: 0,
      createdAt: DateTime(2026, 5, 20),
      updatedAt: DateTime(2026, 5, 20),
    );
  }
}

Product _product() {
  return const Product(
    id: 1,
    name: 'Banh mi bo toi',
    basePrice: 20000,
    category: 'bread',
    active: 1,
    attributes: <String, String>{'trung_bay': 'true'},
  );
}

Widget _buildCheckoutApp({
  required List<PosCartItem> items,
  OrderService? orderService,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/pos', builder: (context, state) => const Text('POS Home')),
      GoRoute(path: '/pos/checkout', builder: (context, state) => const PosCheckoutScreen()),
      GoRoute(
        path: '/pos/receipt/:ref',
        builder: (context, state) => Text('Receipt ${state.pathParameters['ref']}'),
      ),
    ],
    initialLocation: '/pos/checkout',
  );

  return ProviderScope(
    overrides: [
      posCartProvider.overrideWith(() => _SeededPosCartNotifier(items)),
      if (orderService != null) orderServiceProvider.overrideWithValue(orderService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('posCheckoutLocalDueDate', () {
    test('formats local date as yyyy-mm-dd', () {
      final value = posCheckoutLocalDueDate(DateTime(2026, 5, 18, 9, 30));
      expect(value, '2026-05-18');
    });
  });

  group('extractBackendDetail', () {
    test('returns null for null input', () {
      expect(extractBackendDetail(null), isNull);
    });

    test('returns null for non-map input', () {
      expect(extractBackendDetail(['detail']), isNull);
      expect(extractBackendDetail('detail'), isNull);
    });

    test('returns null when detail key is missing', () {
      expect(extractBackendDetail(<String, dynamic>{'message': 'x'}), isNull);
    });

    test('returns null when detail is not a string', () {
      expect(extractBackendDetail(<String, dynamic>{'detail': 123}), isNull);
      expect(extractBackendDetail(<String, dynamic>{'detail': true}), isNull);
    });

    test('returns null when detail is empty or whitespace', () {
      expect(extractBackendDetail(<String, dynamic>{'detail': ''}), isNull);
      expect(extractBackendDetail(<String, dynamic>{'detail': '   '}), isNull);
    });
  });

  group('resolvePosCheckoutErrorMessage', () {
    test('returns backend 422 detail when present', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 422,
          data: {'detail': 'Sản phẩm Bánh su kem không đủ tồn kho'},
        ),
      );

      expect(
        resolvePosCheckoutErrorMessage(error),
        'Sản phẩm Bánh su kem không đủ tồn kho',
      );
    });

    test('returns vietnamese fallback when 422 detail is missing', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 422,
          data: <String, dynamic>{},
        ),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.loiKhongXacDinhTuMayChu);
      expect(
        resolvePosCheckoutErrorMessage(error),
        isNot(contains('DioException')),
      );
    });

    test('returns VN.apiError when DioException response is null', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.apiError);
    });

    test('returns VN.loiMayChu for non-422 server responses', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 500,
          data: <String, dynamic>{'detail': 'Internal Server Error'},
        ),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.loiMayChu);
    });

    test('returns VN.loiHeThong for non-Dio exceptions', () {
      final error = Exception('unexpected');

      expect(resolvePosCheckoutErrorMessage(error), VN.loiHeThong);
    });
  });

  group('checkout interactions', () {
    testWidgets('updates quantity and total after increase and decrease', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text(formatVND(20000)), findsWidgets);

      await tester.tap(find.byTooltip(VN.increaseQuantity));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text(formatVND(40000)), findsOneWidget);

      await tester.tap(find.byTooltip(VN.decreaseQuantity));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text(formatVND(20000)), findsWidgets);
    });

    testWidgets('removes line item and navigates back when cart becomes empty', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.xoa));
      await tester.pumpAndSettle();

      expect(find.text('POS Home'), findsOneWidget);
    });

    testWidgets('submits selected transfer method to order creation', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(
        _buildCheckoutApp(
          items: <PosCartItem>[cartItem],
          orderService: fakeOrderService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.thanhToan));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, VN.xong));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.skip));
      await tester.pumpAndSettle();

      expect(fakeOrderService.paymentMethods, <String?>['transfer']);
      expect(find.text('Receipt ORD-001'), findsOneWidget);
    });

    testWidgets('opens local review before order creation and keeps cart state', (
      tester,
    ) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 2);

      await tester.pumpWidget(
        _buildCheckoutApp(
          items: <PosCartItem>[cartItem],
          orderService: fakeOrderService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.thanhToan));
      await tester.pumpAndSettle();

      expect(fakeOrderService.createOrderCallCount, 0);
      expect(find.text(VN.checkoutReviewTitle), findsWidgets);
      expect(find.text('Banh mi bo toi'), findsOneWidget);
      expect(find.text(VN.xong), findsOneWidget);
      expect(find.text(VN.editOrder), findsOneWidget);
      expect(find.text('Receipt ORD-001'), findsNothing);
    });

    testWidgets('edit order from review preserves cart and selected payment', (
      tester,
    ) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(
        _buildCheckoutApp(
          items: <PosCartItem>[cartItem],
          orderService: fakeOrderService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, VN.thanhToan));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, VN.editOrder));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text(VN.checkoutReviewTitle), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, VN.thanhToan));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, VN.xong));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.skip));
      await tester.pumpAndSettle();

      expect(fakeOrderService.paymentMethods, <String?>['transfer']);
    });

    testWidgets('xong submits create order once while processing and clears after success', (
      tester,
    ) async {
      final createCompleter = Completer<Order>();
      final fakeOrderService = _FakeOrderService(
        createOrderCompleter: createCompleter,
      );
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(
        _buildCheckoutApp(
          items: <PosCartItem>[cartItem],
          orderService: fakeOrderService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.thanhToan));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.xong));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, VN.xong));
      await tester.pump();

      expect(fakeOrderService.createOrderCallCount, 1);
      expect(find.text('POS Home'), findsNothing);

      createCompleter.complete(
        Order(
          id: '2',
          orderRef: 'ORD-LOCK',
          customerName: VN.khachLe,
          items: const [],
          totalPrice: 0,
          createdAt: DateTime(2026, 5, 20),
          updatedAt: DateTime(2026, 5, 20),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Receipt ORD-LOCK'), findsOneWidget);
    });
  });
}
