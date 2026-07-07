import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_stage_indicator.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/stage1_product_selection_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage2_customer_info_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage3_delivery_options_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage4_review_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';

class FixedOrderCreateStateNotifier extends OrderCreateStateNotifier {
  final OrderCreateState initial;
  FixedOrderCreateStateNotifier(this.initial);

  @override
  OrderCreateState build() => initial;
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  final String _url;
  _FakeApiBaseUrlNotifier(this._url);

  @override
  String build() => _url;
}

class _FakePhotoRefreshTickNotifier extends ProductPhotoRefreshTickNotifier {
  _FakePhotoRefreshTickNotifier();

  @override
  int build() => 0;
}

class _FakeCategoriesNotifier extends CategoriesNotifier {
  final List<Category> _categories;
  _FakeCategoriesNotifier(this._categories);

  @override
  Future<List<Category>> build() async => _categories;
}

class _FakeProductsNotifier extends ProductsNotifier {
  final List<Product> _products;
  _FakeProductsNotifier(this._products);

  @override
  Future<List<Product>> build() async => _products;
}

Widget buildTestWidget(Widget child, {OrderCreateState? state}) {
  return ProviderScope(
    overrides: state != null
        ? [
            orderCreateStateProvider.overrideWith(
              () => FixedOrderCreateStateNotifier(state),
            ),
          ]
        : [],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget buildStage1TestWidget(Widget child, {
  OrderCreateState? state,
  List<Product> products = const [],
  List<Category> categories = const [],
}) {
  return ProviderScope(
    overrides: [
      productsProvider.overrideWith(
        () => _FakeProductsNotifier(products),
      ),
      categoriesProvider.overrideWith(
        () => _FakeCategoriesNotifier(categories),
      ),
      apiBaseUrlProvider.overrideWith(
        () => _FakeApiBaseUrlNotifier('http://test.local'),
      ),
      productPhotoRefreshTickProvider.overrideWith(
        () => _FakePhotoRefreshTickNotifier(),
      ),
      if (state != null)
        orderCreateStateProvider.overrideWith(
          () => FixedOrderCreateStateNotifier(state),
        ),
    ],
    child: MaterialApp(home: Scaffold(body: Column(children: [child]))),
  );
}

void _noop() {}

void main() {
  testWidgets('OrderStageIndicator renders 4 stages with currentStage=1',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OrderStageIndicator(currentStage: 1))));

    expect(find.text('Sản phẩm'), findsOneWidget);
    expect(find.text('Khách hàng'), findsOneWidget);
    expect(find.text('Giao hàng'), findsOneWidget);
    expect(find.text('Xem lại'), findsOneWidget);
  });

  testWidgets('OrderStageIndicator renders 4 stages with currentStage=4',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OrderStageIndicator(currentStage: 4))));

    expect(find.byIcon(Icons.check), findsNWidgets(3));
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets(
      'Stage2CustomerInfoScreen renders customer search + source selection',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      Stage2CustomerInfoScreen(onBack: () {}, onContinue: () {}),
    ));

    expect(find.text('Khách hàng'), findsWidgets);
    expect(find.text('Nguồn đặt hàng'), findsOneWidget);
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(find.text('Quay lại'), findsOneWidget);
  });

  testWidgets('Stage3DeliveryOptionsScreen renders delivery type selector',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
    ));

    expect(find.text('Hình thức nhận hàng'), findsOneWidget);
    expect(find.text('Lấy tại tiệm'), findsOneWidget);
    expect(find.text('Giao xe khách'), findsOneWidget);
    expect(find.text('Giao tận nơi'), findsOneWidget);
    expect(find.text('Hạn giao'), findsOneWidget);
    expect(find.text('Tiếp tục'), findsOneWidget);
  });

  testWidgets('Stage4ReviewScreen renders review summary',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: OrderWizardData(
        customerName: 'Test Customer',
        customerPhone: '0123456789',
        deliveryType: 'door',
        deliveryAddress: '123 Test St',
        deliveryPhone: '0987654321',
        shippingFee: 20000,
        notes: 'Test notes',
        source: 'Online',
      ),
      source: 'Online',
      items: [
        DraftOrderItem(
          product: Product(
            id: 1,
            name: 'Test Cake',
            category: 'banh_kem',
            basePrice: 150000,
          ),
          quantity: 2,
        ),
      ],
    );

    await tester.pumpWidget(buildTestWidget(
      Stage4ReviewScreen(onBack: () {}, onSubmit: () {}),
      state: testState,
    ));

    expect(find.text('Tóm tắt đơn hàng'), findsOneWidget);
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('Giao tận nơi'), findsOneWidget);
    expect(find.text('Test Cake x2 — 300.000đ'), findsOneWidget);
    expect(find.text('Tạo đơn hàng'), findsOneWidget);
  });

  testWidgets('Stage1ProductSelectionScreen renders product grid',
      (tester) async {
    final testProduct = Product(
      id: 1,
      name: 'Bánh mì',
      category: 'banh_mi',
      basePrice: 15000,
    );
    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      products: [testProduct],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Chọn sản phẩm'), findsOneWidget);
    expect(find.text('Bánh mì'), findsOneWidget);
  });

  testWidgets('Stage1ProductSelectionScreen shows category chips when provided',
      (tester) async {
    final testProduct = Product(
      id: 1,
      name: 'Bánh mì',
      category: 'banh_mi',
      basePrice: 15000,
    );
    final testCategory = const Category(
      id: 1,
      slug: 'banh_mi',
      name: 'Bánh mì',
      codePrefix: 'BM',
      active: 1,
    );
    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      products: [testProduct],
      categories: [testCategory],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bánh mì'), findsWidgets);
  });

  testWidgets('Stage3DeliveryOptionsScreen shows address fields for door delivery',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: OrderWizardData(deliveryType: 'door'),
    );
    await tester.pumpWidget(buildTestWidget(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: testState,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Địa chỉ giao hàng'), findsOneWidget);
  });

  testWidgets('OrderStageIndicator currentStage=1 shows all step numbers',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OrderStageIndicator(currentStage: 1))));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('Stage2CustomerInfoScreen in POS mode hides source selector',
      (tester) async {
    await tester.pumpWidget(buildTestWidget(
      Stage2CustomerInfoScreen(
        onBack: () {},
        onContinue: () {},
        posMode: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Khách hàng'), findsWidgets);
    expect(find.text('Nguồn đặt hàng'), findsNothing);
  });
}
