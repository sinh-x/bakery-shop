// DG-414 Phase 4.4 — Flutter widget test for the "Đổi sản phẩm" swap flow.
// Verifies FR6 (swap action in WorkItemEditCard) and the client-side half of
// AC1/AC5: tapping the swap button opens ProductPickerPage, selecting a
// product PATCHes only `productId`/`productName` (all other fields are
// omitted so the backend's `exclude_unset` preserves them).
// ignore_for_file: prefer_const_declarations // DG-138#todo: const audit
import 'dart:convert';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/data/providers/categories_provider.dart';
import 'package:bakery_app/data/providers/order/order_detail_notifier.dart';
import 'package:bakery_app/data/providers/order/order_work_item_providers.dart';
import 'package:bakery_app/data/providers/products_provider.dart';
import 'package:bakery_app/features/orders/order_edit/widgets/work_item_edit_card.dart';
import 'package:bakery_app/features/orders/widgets/product_picker_page.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captured PATCH /api/orders/{ref}/items/{id} body (the swap call).
Map<String, dynamic>? _patchBody;

WorkItem _richItem() {
  return const WorkItem(
    id: '10',
    orderId: 'ORD-SWAP',
    productId: 'P-OLD',
    productName: 'Bánh cũ',
    quantity: 3,
    unitPrice: 250000,
    assignedPrice: 200000,
    notes: 'ghi chú cũ',
    status: 'pending',
    isBirthday: true,
    isExtra: false,
    isGift: true,
    age: 5,
    attributes: <String, dynamic>{
      'candle_type': 'nen_so',
      'price_chip_label': 'Nhỏ',
    },
    blanks: <BlankAssignment>[
      BlankAssignment(id: 1, blankId: 99, blankName: 'Phôi A', quantity: 2),
    ],
  );
}

const _oldProduct = Product(
  id: 1,
  name: 'Bánh cũ',
  category: 'banh_kem',
  basePrice: 250000,
  active: 1,
  productCode: 'P-OLD',
);

const _newProduct = Product(
  id: 2,
  name: 'Bánh mới',
  category: 'banh_kem',
  basePrice: 300000,
  active: 1,
  productCode: 'P-NEW',
);

const _categories = <Category>[
  Category(
    id: 1,
    slug: 'banh_kem',
    name: 'Bánh kem',
    codePrefix: 'BK',
    active: 1,
  ),
];

/// Dio interceptor that mocks the swap PATCH + order-detail refresh + photos
/// GET. Captures the PATCH body so the test can assert only `productId` and
/// `productName` were sent (FR2/AC1: preserve all other fields).
class _SwapInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final method = options.method;

    // PATCH /api/orders/ORD-SWAP/items/10 — the swap call from
    // OrderWorkItemsNotifier.edit -> WorkItemService.updateWorkItem.
    if (path == '/api/orders/ORD-SWAP/items/10' && method == 'PATCH') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
      _patchBody = body;
      // Return the authoritative replacement. The backend preserves workflow
      // attributes but prunes the incompatible old product price-chip label.
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{
            'id': '10',
            'orderId': 'ORD-SWAP',
            'productId': body['productId'] ?? 'P-OLD',
            'productName': body['productName'] ?? 'Bánh cũ',
            'quantity': 3,
            'unitPrice': 250000,
            'assignedPrice': 200000,
            'notes': 'ghi chú cũ',
            'status': 'pending',
            'isBirthday': true,
            'isExtra': false,
            'isGift': true,
            'age': 5,
            'attributes': <String, dynamic>{'candle_type': 'nen_so'},
            'blanks': <Map<String, dynamic>>[
              {'id': 1, 'blankId': 99, 'blankName': 'Phôi A', 'quantity': 2.0},
            ],
          },
        ),
      );
      return;
    }

    // GET /api/orders/ORD-SWAP — order-detail refresh after edit.
    if (path == '/api/orders/ORD-SWAP' && method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{
            'id': 'order-swap',
            'orderRef': 'ORD-SWAP',
            'publicOrderCode': '',
            'customerName': 'Test',
            'customerPhone': '',
            'deliveryPhone': '',
            'customerId': null,
            'items': <Map<String, dynamic>>[],
            'totalPrice': 0.0,
            'status': 'new',
            'deliveryType': 'pickup',
            'deliveryAddress': '',
            'shippingFee': 0.0,
            'notes': '',
            'source': '',
            'packingChecklist': <Map<String, dynamic>>[],
            'createdAt': '2026-08-19T00:00:00Z',
            'updatedAt': '2026-08-19T00:00:00Z',
          },
        ),
      );
      return;
    }

    // GET /api/orders/ORD-SWAP/photos — order photos (empty).
    if (path.startsWith('/api/orders/ORD-SWAP/photos') && method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <Map<String, dynamic>>[],
        ),
      );
      return;
    }

    // GET /api/orders/ORD-SWAP/items — initial work-items list load.
    if (path == '/api/orders/ORD-SWAP/items' && method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': '10',
              'orderId': 'ORD-SWAP',
              'productId': 'P-OLD',
              'productName': 'Bánh cũ',
              'quantity': 3,
              'unitPrice': 250000,
              'assignedPrice': 200000,
              'notes': 'ghi chú cũ',
              'status': 'pending',
              'isBirthday': true,
              'isGift': true,
              'age': 5,
              'attributes': <String, dynamic>{
                'candle_type': 'nen_so',
                'price_chip_label': 'Nhỏ',
              },
              'blanks': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 1,
                  'blankId': 99,
                  'blankName': 'Phôi A',
                  'quantity': 2.0,
                },
              ],
            },
          ],
        ),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}

class _FakeProductsNotifier extends ProductsNotifier {
  _FakeProductsNotifier(this._products);
  final List<Product> _products;

  @override
  Future<List<Product>> build() async => _products;
}

class _FakeCategoriesNotifier extends CategoriesNotifier {
  _FakeCategoriesNotifier(this._categories);
  final List<Category> _categories;

  @override
  Future<List<Category>> build() async => _categories;
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  _FakeApiBaseUrlNotifier(this._url);
  final String _url;

  @override
  String build() => _url;
}

class _FakePhotoRefreshTickNotifier extends ProductPhotoRefreshTickNotifier {
  @override
  int build() => 0;
}

class _FailOnceOrderDetailNotifier extends OrderDetailNotifier {
  _FailOnceOrderDetailNotifier() : super('ORD-SWAP');

  int refreshCalls = 0;

  @override
  Future<Order> build() async => Order.fromJson(<String, dynamic>{
    'id': 'order-swap',
    'orderRef': 'ORD-SWAP',
    'publicOrderCode': '',
    'customerName': 'Test',
    'customerPhone': '',
    'deliveryPhone': '',
    'items': <Map<String, dynamic>>[],
    'totalPrice': 0.0,
    'status': 'new',
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'shippingFee': 0.0,
    'packingChecklist': <Map<String, dynamic>>[],
    'createdAt': '2026-08-29T00:00:00Z',
    'updatedAt': '2026-08-29T00:00:00Z',
  });

  @override
  Future<Object?> refresh() async {
    refreshCalls += 1;
    if (refreshCalls == 1) {
      return DioException(
        requestOptions: RequestOptions(path: '/api/orders/ORD-SWAP'),
        type: DioExceptionType.connectionTimeout,
      );
    }
    return null;
  }
}

Future<ProviderContainer> _buildContainer(
  Interceptor interceptor, {
  bool failDetailRefreshOnce = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..interceptors.add(interceptor);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(dio),
      apiBaseUrlProvider.overrideWith(
        () => _FakeApiBaseUrlNotifier('http://test.local'),
      ),
      productsProvider.overrideWith(
        () => _FakeProductsNotifier(<Product>[_oldProduct, _newProduct]),
      ),
      categoriesProvider.overrideWith(
        () => _FakeCategoriesNotifier(_categories),
      ),
      productPhotoRefreshTickProvider.overrideWith(
        _FakePhotoRefreshTickNotifier.new,
      ),
      if (failDetailRefreshOnce)
        orderDetailProvider(
          'ORD-SWAP',
        ).overrideWith(_FailOnceOrderDetailNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpCard(
  WidgetTester tester,
  WorkItem item,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkItemEditCard(orderRef: 'ORD-SWAP', item: item),
          ),
        ),
      ),
    ),
  );
  // productsProvider + categoriesProvider resolve async.
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _patchBody = null;
  });

  group('DG-414 Phase 4.4: WorkItemEditCard "Đổi sản phẩm" swap flow', () {
    testWidgets(
      'FR6: swap button has the "Đổi sản phẩm" tooltip and is rendered on the item header',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        // FR6/FR7: the change-product IconButton uses Icons.swap_horiz with
        // the centralized OrdersLabels.changeProduct tooltip ("Đổi sản phẩm").
        final swapButton = find.widgetWithIcon(IconButton, Icons.swap_horiz);
        expect(
          swapButton,
          findsOneWidget,
          reason: 'FR6: WorkItemEditCard should expose the swap action button',
        );

        final tooltip = tester.widget<IconButton>(swapButton).tooltip;
        expect(
          tooltip,
          OrdersLabels.changeProduct,
          reason:
              'FR7: swap button tooltip should use the centralized VN label',
        );
      },
    );

    testWidgets(
      'AC1/AC5: tapping "Đổi sản phẩm" opens ProductPickerPage and PATCHes only productId/productName',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        // Item header shows the original product name before the swap.
        expect(find.text('Bánh cũ'), findsOneWidget);

        // Tap the swap button (FR6) to open ProductPickerPage.
        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();

        // ProductPickerPage is pushed full-screen (single-select mode).
        expect(
          find.byType(ProductPickerPage),
          findsOneWidget,
          reason: 'FR6: tapping swap should open ProductPickerPage',
        );

        // The new product is visible in the picker grid (active products only).
        expect(find.text('Bánh mới'), findsOneWidget);

        // Tap the new product -> _selectSingleProduct -> picker pops -> edit() PATCHes.
        await tester.tap(find.text('Bánh mới'));
        await tester.pumpAndSettle();

        // The picker has closed and the swap PATCH has fired.
        expect(find.byType(ProductPickerPage), findsNothing);
        expect(
          _patchBody,
          isNotNull,
          reason: 'AC1: selecting a product must trigger a PATCH /items/{id}',
        );

        // FR2/AC1/AC5: only productId and productName are sent — quantity,
        // notes, isBirthday, age, isExtra, isGift, attributes, assignedPrice,
        // and unitPrice are all omitted so the backend exclude_unset keeps
        // them intact (blanks live in a separate junction table, untouched).
        expect(
          _patchBody!.keys.toSet(),
          <String>{'productId', 'productName'},
          reason:
              'AC1/AC5: swap PATCH must send only productId + productName; '
              'all other fields must be omitted so they are preserved',
        );
        expect(
          _patchBody!['productId'],
          'P-NEW',
          reason: 'AC1: productId should update to the new product code',
        );
        expect(
          _patchBody!['productName'],
          'Bánh mới',
          reason: 'AC1: productName should update to the new product name',
        );
        final serverItem = container
            .read(orderWorkItemsProvider('ORD-SWAP'))
            .requireValue
            .singleWhere((item) => item.id == '10');
        expect(serverItem.productName, 'Bánh mới');
        expect(serverItem.attributes['candle_type'], 'nen_so');
        expect(serverItem.attributes.containsKey('price_chip_label'), isFalse);

        // Explicitly assert the preserved fields were NOT sent.
        for (final preservedKey in <String>[
          'quantity',
          'unitPrice',
          'assignedPrice',
          'notes',
          'isBirthday',
          'age',
          'isExtra',
          'isGift',
          'attributes',
          'position',
        ]) {
          expect(
            _patchBody!.containsKey(preservedKey),
            isFalse,
            reason:
                'AC1/AC5: $preservedKey must NOT be sent on swap so the '
                'backend preserves the existing value',
          );
        }
      },
    );

    testWidgets(
      'AC2: swap PATCH does not send unitPrice or assignedPrice (price unchanged)',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bánh mới'));
        await tester.pumpAndSettle();

        expect(_patchBody, isNotNull);
        // AC2/NFR1: unitPrice/assignedPrice are NOT in the PATCH body, so the
        // backend keeps the existing price. The client only swaps the product
        // identity; price is left untouched (FR3).
        expect(
          _patchBody!.containsKey('unitPrice'),
          isFalse,
          reason: 'AC2: unitPrice must not be sent on swap so it is preserved',
        );
        expect(
          _patchBody!.containsKey('assignedPrice'),
          isFalse,
          reason:
              'AC2: assignedPrice must not be sent on swap so it is preserved',
        );
      },
    );

    testWidgets(
      'NFR1: cancel the picker without selecting leaves the item untouched (no PATCH)',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        // Open the picker.
        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();
        expect(find.byType(ProductPickerPage), findsOneWidget);

        // Close the picker via the close (X) button — no selection made.
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pumpAndSettle();

        // Picker is dismissed and no PATCH was fired.
        expect(find.byType(ProductPickerPage), findsNothing);
        expect(
          _patchBody,
          isNull,
          reason: 'NFR1: cancelling the picker must not mutate the item',
        );
        // Original product name is still shown.
        expect(find.text('Bánh cũ'), findsOneWidget);
      },
    );

    testWidgets(
      'UI-1 (DG-414 review): swap button is disabled when item is delivered',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        final delivered = _richItem().copyWith(status: 'delivered');
        await _pumpCard(tester, delivered, container);

        final swapButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.swap_horiz),
        );
        // FR5/UI-1: swap button onPressed is null when status is delivered,
        // so tapping it does nothing (the backend would 422 the PATCH).
        expect(
          swapButton.onPressed,
          isNull,
          reason: 'UI-1: swap button must be disabled on delivered items',
        );
      },
    );

    testWidgets(
      'UI-1 (DG-414 review): swap button is disabled when item is cancelled',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        final cancelled = _richItem().copyWith(status: 'cancelled');
        await _pumpCard(tester, cancelled, container);

        final swapButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.swap_horiz),
        );
        expect(
          swapButton.onPressed,
          isNull,
          reason: 'UI-1: swap button must be disabled on cancelled items',
        );
      },
    );

    testWidgets(
      'UI-1 (DG-414 review): swap button stays enabled on non-terminal status',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        // pending is the default in _richItem(); assert the button is enabled.
        await _pumpCard(tester, _richItem(), container);

        final swapButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.swap_horiz),
        );
        expect(
          swapButton.onPressed,
          isNotNull,
          reason: 'UI-1: swap button should remain enabled on pending items',
        );
      },
    );

    testWidgets(
      'AC2: remove button is disabled for delivered and cancelled items',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());

        for (final status in <String>['delivered', 'cancelled']) {
          await _pumpCard(
            tester,
            _richItem().copyWith(status: status),
            container,
          );
          final removeButton = tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.close),
          );
          expect(removeButton.tooltip, OrdersLabels.removeProduct);
          expect(
            removeButton.onPressed,
            isNull,
            reason: 'removal must be disabled when status is $status',
          );
        }
      },
    );

    testWidgets(
      'AC8: successful replacement survives refresh failure and exposes retry',
      (tester) async {
        final container = await _buildContainer(
          _SwapInterceptor(),
          failDetailRefreshOnce: true,
        );
        await _pumpCard(tester, _richItem(), container);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bánh mới'));
        await tester.pumpAndSettle();

        final visibleItem = container
            .read(orderWorkItemsProvider('ORD-SWAP'))
            .requireValue
            .singleWhere((item) => item.id == '10');
        expect(visibleItem.productName, 'Bánh mới');
        expect(
          find.textContaining(OrdersLabels.replaceProductRefreshFailed),
          findsOneWidget,
        );
        expect(
          find.textContaining(SharedLabels.failureReasonLabel),
          findsOneWidget,
        );
        expect(find.textContaining(SharedLabels.nextStepLabel), findsOneWidget);
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.action?.label, SharedLabels.retry);

        await tester.tap(find.text(SharedLabels.retry));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text(OrdersLabels.orderDetailRefreshSucceeded),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AC8: successful removal survives refresh failure and exposes retry',
      (tester) async {
        final container = await _buildContainer(
          _RemoveInterceptor(),
          failDetailRefreshOnce: true,
        );
        await _pumpCard(tester, _richItem(), container);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, SharedLabels.remove));
        await tester.pumpAndSettle();

        expect(
          container.read(orderWorkItemsProvider('ORD-SWAP')).requireValue,
          isEmpty,
        );
        expect(
          find.textContaining(OrdersLabels.removeProductRefreshFailed),
          findsOneWidget,
        );
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.action?.label, SharedLabels.retry);
      },
    );

    testWidgets(
      'CQ-1 (DG-414 review): swap PATCH failure surfaces a top snack bar error',
      (tester) async {
        final container = await _buildContainer(_FailingSwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        // Tap swap, pick the new product, the PATCH 422s — _changeProduct
        // must catch the error and surface a SnackBar (no unhandled throw).
        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bánh mới'));
        await tester.pumpAndSettle();

        // CQ-1/AC9: feedback names the action, normalized reason, and next
        // step without interpolating the Dio exception.
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason: 'CQ-1: swap failure must surface user-visible feedback',
        );
        expect(
          find.textContaining(OrdersLabels.replaceProductFailed),
          findsOneWidget,
        );
        expect(
          find.textContaining(SharedLabels.failureReasonLabel),
          findsOneWidget,
        );
        expect(find.textContaining(SharedLabels.nextStepLabel), findsOneWidget);
        expect(find.textContaining('DioException'), findsNothing);
      },
    );

    testWidgets(
      'AC9: remove failure has Vietnamese action, reason, and next step',
      (tester) async {
        final container = await _buildContainer(_FailingRemoveInterceptor());
        await _pumpCard(tester, _richItem(), container);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, SharedLabels.remove));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(OrdersLabels.removeProductFailed),
          findsOneWidget,
        );
        expect(
          find.textContaining(SharedLabels.failureReasonLabel),
          findsOneWidget,
        );
        expect(find.textContaining(SharedLabels.nextStepLabel), findsOneWidget);
        expect(find.textContaining('DioException'), findsNothing);
      },
    );

    testWidgets(
      'UI-2 (DG-414 review cycle1): swap picker does not enter multi-select on long-press',
      (tester) async {
        final container = await _buildContainer(_SwapInterceptor());
        await _pumpCard(tester, _richItem(), container);

        // Open the swap picker (ProductPickerPage pushed via _changeProduct).
        await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
        await tester.pumpAndSettle();
        expect(find.byType(ProductPickerPage), findsOneWidget);

        // Long-press a product — in single-select mode this must NOT enter
        // multi-select (UI-2 fix: long-press entry point disabled when
        // singleSelect: true is passed from _changeProduct).
        await tester.longPress(find.text('Bánh mới'));
        await tester.pumpAndSettle();

        // The multi-select confirm action (check IconButton in the app bar)
        // is only rendered when _multiSelectMode is true. Since long-press
        // is disabled, the check action must remain absent.
        final checkActions = find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithIcon(IconButton, Icons.check),
        );
        expect(
          checkActions,
          findsNothing,
          reason:
              'UI-2: long-press must not enable multi-select in the '
              'swap picker (singleSelect: true)',
        );

        // The app bar title also reflects multi-select mode via the
        // "N đã chọn" string; assert it never appears.
        expect(
          find.textContaining('đã chọn'),
          findsNothing,
          reason:
              'UI-2: multi-select count title must not appear in '
              'single-select swap picker',
        );
      },
    );
  });
}

/// Interceptor that rejects the swap PATCH with a 422 (mirrors the backend's
/// FR5/SEC-1 rejection). Used by the CQ-1 error-handling test.
class _RemoveInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders/ORD-SWAP/items/10' &&
        options.method == 'DELETE') {
      handler.resolve(Response<void>(requestOptions: options, statusCode: 204));
      return;
    }
    _SwapInterceptor().onRequest(options, handler);
  }
}

class _FailingRemoveInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders/ORD-SWAP/items/10' &&
        options.method == 'DELETE') {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 422,
            data: <String, dynamic>{'detail': 'Không thể xóa sản phẩm đã giao'},
          ),
        ),
      );
      return;
    }
    _SwapInterceptor().onRequest(options, handler);
  }
}

class _FailingSwapInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final method = options.method;

    if (path == '/api/orders/ORD-SWAP/items/10' && method == 'PATCH') {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 422,
            data: <String, dynamic>{'detail': 'Không thể đổi sản phẩm'},
          ),
        ),
      );
      return;
    }
    // Other routes (order-detail refresh, photos, items list) — reuse the
    // success stubs from _SwapInterceptor by delegating.
    _SwapInterceptor().onRequest(options, handler);
  }
}
