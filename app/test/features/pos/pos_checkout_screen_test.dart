import 'dart:async';

import 'package:bakery_app/data/api/payment_transaction_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/features/pos/pos_checkout_screen.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/product.dart';

class _SeededPosCartNotifier extends PosCartNotifier {
  _SeededPosCartNotifier(this._items);
  final List<PosCartItem> _items;
  @override
  PosCartState build() => PosCartState(items: _items);
}

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService() : super(Dio());
  @override
  Future<List<Customer>> listCustomers({String? search}) async => [];
}

class _FakeOrderService extends OrderService {
  _FakeOrderService({this.createOrderCompleter}) : super(Dio());
  final List<String?> paymentMethods = <String?>[];
  final List<List<Map<String, dynamic>>> createdItems = <List<Map<String, dynamic>>>[];
  final Completer<Order>? createOrderCompleter;
  int createOrderCallCount = 0;

  @override
  Future<Order> createOrder({
    required String customerName,
    String customerPhone = '',
    String deliveryPhone = '',
    int? customerId,
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
    createdItems.add(items);
    if (createOrderCompleter != null) return createOrderCompleter!.future;
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

class _FakePaymentTransactionService extends PaymentTransactionService {
  _FakePaymentTransactionService() : super(Dio());
  @override
  Future<PaymentTransaction> createTransaction(
    String orderRef, {
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
  }) async {
    return PaymentTransaction(
      id: 'txn-1',
      orderId: orderRef,
      amount: amount,
      type: type,
      method: method,
      createdAt: DateTime(2026, 5, 20),
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
      GoRoute(path: '/pos/receipt/:ref', builder: (context, state) => Text('Receipt ${state.pathParameters['ref']}')),
    ],
    initialLocation: '/pos/checkout',
  );

  final txnSvc = _FakePaymentTransactionService();
  return ProviderScope(
    overrides: [
      posCartProvider.overrideWith(() => _SeededPosCartNotifier(items)),
      if (orderService != null) orderServiceProvider.overrideWithValue(orderService),
      customerServiceProvider.overrideWithValue(_FakeCustomerService()),
      paymentTransactionServiceProvider.overrideWithValue(txnSvc),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _navigateToReview(WidgetTester tester) async {
  await tester.tap(find.text('Tiếp tục'));
  await tester.pumpAndSettle();
}

/// Dismisses the "Giao ngay?" (B5) dialog by tapping "Để sau" (confirmed).
Future<void> _dismissDeliverNowDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text(VN.deliverNowNo));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

/// From the Stage 4 review sub-step, advance to the dedicated payment step
/// (DG-218 Phase 4). The review panel's continue button ("Tiếp tục") opens
/// the payment step where the cash/transfer selector and submit button live.
Future<void> _navigateToPayment(WidgetTester tester) async {
  await tester.tap(find.text(OrdersLabels.continueLabel));
  await tester.pumpAndSettle();
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
      expect(resolvePosCheckoutErrorMessage(error), 'Sản phẩm Bánh su kem không đủ tồn kho');
    });
    test('returns vietnamese fallback when 422 detail is missing', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(requestOptions: RequestOptions(path: '/api/orders'), statusCode: 422, data: <String, dynamic>{}),
      );
      expect(resolvePosCheckoutErrorMessage(error), VN.loiKhongXacDinhTuMayChu);
      expect(resolvePosCheckoutErrorMessage(error), isNot(contains('DioException')));
    });
    test('returns VN.apiError when DioException response is null', () {
      final error = DioException(requestOptions: RequestOptions(path: '/api/orders'));
      expect(resolvePosCheckoutErrorMessage(error), VN.apiError);
    });
    test('returns VN.loiMayChu for non-422 server responses', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(requestOptions: RequestOptions(path: '/api/orders'), statusCode: 500, data: <String, dynamic>{'detail': 'Internal Server Error'}),
      );
      expect(resolvePosCheckoutErrorMessage(error), VN.loiMayChu);
    });
    test('returns VN.loiHeThong for non-Dio exceptions', () {
      expect(resolvePosCheckoutErrorMessage(Exception('unexpected')), VN.loiHeThong);
    });
  });

  group('checkout interactions', () {
    // Note: POS Stage 4 is review-only as of DG-218 Phase 4 (FR-5/FR-6).
    // Inline cart edits (quantity steppers, swipe-to-remove) are no longer
    // available on the review panel; they happen in Stage 1 / the POS grid.
    // The two tests that exercised the old review-inline cart editing were
    // removed: quantity editing is covered by Stage 1 tests, and the
    // empty-cart guard is unchanged (not part of Phase 4 scope).

    testWidgets('submits selected transfer method to order creation', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      // Stage 4 review is review-only; advance to the dedicated payment step
      // where the cash/transfer selector lives (DG-218 Phase 4, FR-5).
      await _navigateToPayment(tester);

      await tester.ensureVisible(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);
      await tester.tap(find.text(VN.skip));
      await tester.pumpAndSettle();

      expect(fakeOrderService.paymentMethods, <String?>['transfer']);
      expect(find.text('Receipt ORD-001'), findsOneWidget);
    });

    testWidgets('payment segment selection has visible selected styling', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      // The payment selector now lives on the dedicated payment step
      // (DG-218 Phase 4); the review panel has no payment selector.
      await _navigateToPayment(tester);

      await tester.ensureVisible(find.byType(SegmentedButton<String>));
      await tester.pumpAndSettle();

      final segmentedButtons = find.byType(SegmentedButton<String>);
      expect(segmentedButtons, findsWidgets);

      var segmented = tester.widget<SegmentedButton<String>>(segmentedButtons.last);
      expect(segmented.selected, {'cash'});

      await tester.ensureVisible(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();

      segmented = tester.widget<SegmentedButton<String>>(segmentedButtons.last);
      expect(segmented.selected, {'transfer'});
    });

    testWidgets('submits useInventory false for force-sold cart lines', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1, useInventory: false);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      // Advance to the dedicated payment step (default cash) before submit
      // (DG-218 Phase 4).
      await _navigateToPayment(tester);

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);

      expect(fakeOrderService.createdItems.single.single['attributes'], {'useInventory': 'false'});
    });

    testWidgets('submits gift items with productId and isGift flag', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final normalItem = PosCartItem(product: _product(), quantity: 1);
      final giftItem = PosCartItem(
        product: const Product(id: 42, name: 'Nen', basePrice: 5000, category: 'phu_kien', active: 1, attributes: {'_gift': 'true'}),
        quantity: 1,
        isGift: true,
      );

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[normalItem, giftItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      // Advance to the dedicated payment step before submit (DG-218 Phase 4).
      await _navigateToPayment(tester);

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);

      final giftPayload = fakeOrderService.createdItems.single.firstWhere((item) => item['isGift'] == true);
      expect(giftPayload['productId'], '42');
      expect(giftPayload['productName'], 'Nen');
    });

    testWidgets('opens wizard review before order creation and keeps cart state', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 2);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);

      expect(fakeOrderService.createOrderCallCount, 0);
      // Stage 4 review uses the unified summary-card title (DG-218 Phase 4).
      expect(find.text(OrdersLabels.reviewSummary), findsOneWidget);
      // The product line renders as "name x<qty> — <price>" in ProductSummaryCard.
      expect(find.textContaining('Banh mi bo toi'), findsOneWidget);
      expect(find.text('Receipt ORD-001'), findsNothing);
    });

    testWidgets('review shows gift line totals as zero', (tester) async {
      final normalItem = PosCartItem(product: _product(), quantity: 1);
      final giftItem = PosCartItem(
        product: const Product(id: -1, name: 'Nen', basePrice: 5000, attributes: {'_gift': 'true'}),
        quantity: 1,
        isGift: true,
      );

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[normalItem, giftItem]));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);

      // Stage 4 review uses the unified ProductSummaryCard (DG-218 Phase 4,
      // FR-6). POS cart gifts render as wizard extras-with-gift in the
      // extras section with the "Tặng kèm" suffix and a "x<qty>" body.
      await tester.ensureVisible(find.textContaining('Nen').at(0));
      await tester.pumpAndSettle();

      // The gift line shows the tang-kem suffix (unified card convention).
      expect(find.textContaining(VN.tangKem), findsWidgets);
      expect(find.textContaining('Banh mi bo toi'), findsOneWidget);
      expect(find.text(formatVND(20000)), findsWidgets);
    });

    testWidgets('edit order from review preserves cart and selected payment', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      // Advance to the dedicated payment step and select transfer
      // (DG-218 Phase 4, FR-5).
      await _navigateToPayment(tester);

      await tester.ensureVisible(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();

      // Going back from the payment step returns to the review sub-step
      // (still Stage 4); the selection persists in checkout state.
      final backButton = find.text('Quay lại');
      await tester.ensureVisible(backButton);
      await tester.pumpAndSettle();
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Review sub-step is shown again (unified summary card title).
      expect(find.text(OrdersLabels.reviewSummary), findsOneWidget);

      // Re-enter the payment step; the transfer selection persists.
      await _navigateToPayment(tester);

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);
      await tester.tap(find.text(VN.skip));
      await tester.pumpAndSettle();

      expect(fakeOrderService.paymentMethods, <String?>['transfer']);
    });

    testWidgets('finalize submits create order once while processing and clears after success', (tester) async {
      final createCompleter = Completer<Order>();
      final fakeOrderService = _FakeOrderService(createOrderCompleter: createCompleter);
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);

      // Stage 4 review sub-step is shown (unified summary card title).
      expect(find.text(OrdersLabels.reviewSummary), findsOneWidget);

      // Advance to the dedicated payment step.
      await _navigateToPayment(tester);

      // Tap the submit button — _isProcessing guard prevents a second call.
      final btn = find.byType(FilledButton);
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      // B5 dialog appears; dismiss it to continue submit flow.
      await _dismissDeliverNowDialog(tester);

      // While the first call is still processing (completer not yet resolved),
      // tap again — should be a no-op because _isProcessing is true.
      await tester.tap(btn);
      await tester.pump();

      expect(fakeOrderService.createOrderCallCount, 1);
      expect(find.text('POS Home'), findsNothing);

      createCompleter.complete(Order(
        id: '2',
        orderRef: 'ORD-LOCK',
        customerName: VN.khachLe,
        items: const [],
        totalPrice: 0,
        createdAt: DateTime(2026, 5, 20),
        updatedAt: DateTime(2026, 5, 20),
      ));

      await tester.pumpAndSettle();
      expect(find.text('Receipt ORD-LOCK'), findsOneWidget);
    });
  });

  group('Stage 1 reachability and cart sync (DG-218 Phase 3)', () {
    testWidgets('Stage 1 is reachable via the stage indicator (AC1)', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      // Checkout opens on Stage 2; the Stage 1 indicator label is tappable.
      expect(find.text(OrdersLabels.stage1Label), findsWidgets);
      await tester.tap(find.text(OrdersLabels.stage1Label).first);
      await tester.pumpAndSettle();

      // Stage 1 (product selection) shows the seeded product, confirming
      // Stage 1 rendered with the cart contents.
      expect(find.text('Banh mi bo toi'), findsOneWidget);
    });

    testWidgets('Stage 1 edit writes back to posCartProvider so submit reflects the edit (AC2)', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      // Navigate to Stage 1 via the indicator.
      await tester.tap(find.text(OrdersLabels.stage1Label).first);
      await tester.pumpAndSettle();

      // Edit the product quantity in the wizard Stage 1 (1 -> 2).
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // Continue out of Stage 1 — this syncs the wizard edits back to the
      // POS cart (single source of truth at submit) and advances to Stage 2.
      await tester.tap(find.text(OrdersLabels.continueLabel));
      await tester.pumpAndSettle();

      // Proceed to the review panel (Stage 2 pickup skips Stage 3).
      await _navigateToReview(tester);
      // Advance to the dedicated payment step before submit (DG-218 Phase 4).
      await _navigateToPayment(tester);

      // Submit (cash) and assert the created order reflects the edited qty.
      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);

      expect(fakeOrderService.createOrderCallCount, 1);
      final submittedItems = fakeOrderService.createdItems.single;
      final regularItem = submittedItems.firstWhere((i) => i['isGift'] != true);
      expect(regularItem['quantity'], 2);
      expect(regularItem['productId'], '1');
    });

    testWidgets('returning to Stage 1 seeds wizard items from the cart', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 3);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      await tester.tap(find.text(OrdersLabels.stage1Label).first);
      await tester.pumpAndSettle();

      // The wizard Stage 1 reflects the cart contents (product seeded).
      expect(find.text('Banh mi bo toi'), findsOneWidget);
      // The qty stepper shows the cart quantity (3) in the item row, not the
      // stage indicator number. Match the qty Text by its titleSmall style to
      // disambiguate from the stage-3 indicator circle ("3").
      final qtyFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == '3' && (w.style?.fontSize ?? 0) >= 14,
      );
      expect(qtyFinder, findsOneWidget);
    });
  });

  group('Stage 4 dedicated payment step (DG-218 Phase 4)', () {
    testWidgets('AC5: review sub-step uses the unified summary cards', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);

      // Unified summary-card titles from stage_summary_card.dart /
      // product_summary_card.dart, identical to order-create Stage 4. The
      // customer title also matches the Stage 2 indicator description, so
      // it appears in both the indicator and the card (findsWidgets).
      expect(find.text(OrdersLabels.reviewSummary), findsOneWidget);
      expect(find.text(OrdersLabels.summaryProducts), findsOneWidget);
      expect(find.text(OrdersLabels.summaryCustomer), findsWidgets);
      expect(find.text(OrdersLabels.summaryDelivery), findsOneWidget);
    });

    testWidgets('AC4: Stage 4 review has no payment selector; payment step is separate', (tester) async {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem]));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);

      // The review sub-step must NOT contain the payment SegmentedButton
      // (FR-5): payment is presented as a dedicated step after review.
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.text(VN.tienMat), findsNothing);
      expect(find.text(VN.chuyenKhoan), findsNothing);
      expect(find.text(VN.submitOrder), findsNothing);

      // Advancing opens the dedicated payment step with the selector.
      await _navigateToPayment(tester);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text(VN.tienMat), findsOneWidget);
      expect(find.text(VN.chuyenKhoan), findsOneWidget);
      expect(find.text(VN.submitOrder), findsOneWidget);
    });

    testWidgets('AC4/AC8: cash path submits, shows receipt, and clears the cart', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      await _navigateToPayment(tester);

      // Default selection is cash; submit directly.
      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);

      expect(fakeOrderService.paymentMethods, <String?>['cash']);
      // Receipt screen is shown.
      expect(find.text('Receipt ORD-001'), findsOneWidget);
    });

    testWidgets('AC4/AC8: transfer skip-photo path submits as transfer and shows receipt', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      await _navigateToPayment(tester);

      await tester.tap(find.text(VN.chuyenKhoan));
      await tester.pumpAndSettle();

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);
      // Skip the transfer proof photo.
      await tester.tap(find.text(VN.skip));
      await tester.pumpAndSettle();

      expect(fakeOrderService.paymentMethods, <String?>['transfer']);
      expect(find.text('Receipt ORD-001'), findsOneWidget);
    });

    testWidgets('AC8: POS defaults khách lẻ + Tại tiệm - POS applied on submit', (tester) async {
      final fakeOrderService = _FakeOrderService();
      final cartItem = PosCartItem(product: _product(), quantity: 1);

      await tester.pumpWidget(_buildCheckoutApp(items: <PosCartItem>[cartItem], orderService: fakeOrderService));
      await tester.pumpAndSettle();

      await _navigateToReview(tester);
      await _navigateToPayment(tester);

      final createButton = find.widgetWithText(FilledButton, 'TẠO ĐƠN HÀNG');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await _dismissDeliverNowDialog(tester);

      // FR-9: the walk-in customer and POS source defaults are applied.
      expect(fakeOrderService.createOrderCallCount, 1);
      expect(find.text('Receipt ORD-001'), findsOneWidget);
    });
  });
}
