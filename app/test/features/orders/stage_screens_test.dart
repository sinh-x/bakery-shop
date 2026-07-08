import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_stage_indicator.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/product_picker_page.dart';
import 'package:bakery_app/features/orders/widgets/stage1_product_selection_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage2_customer_info_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage3_delivery_options_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage4_review_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';

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
        _FakePhotoRefreshTickNotifier.new,
      ),
      if (state != null)
        orderCreateStateProvider.overrideWith(
          () => FixedOrderCreateStateNotifier(state),
        ),
    ],
    child: MaterialApp(home: Scaffold(body: Column(children: [Expanded(child: child)]))),
  );
}

void _noop() {}

void main() {
  testWidgets('OrderStageIndicator renders 4 stages with currentStage=1',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrderStageIndicator(currentStage: 1))));

    expect(find.text('Sản phẩm'), findsOneWidget);
    expect(find.text('Khách hàng'), findsOneWidget);
    expect(find.text('Giao hàng'), findsOneWidget);
    expect(find.text('Xem lại'), findsOneWidget);
  });

  testWidgets('OrderStageIndicator renders 4 stages with currentStage=4',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrderStageIndicator(currentStage: 4))));

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
      wizardData: const OrderWizardData(
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
          product: const Product(
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

  testWidgets('Stage1ProductSelectionScreen shows empty state with (+) button when no items (AC-1)',
      (tester) async {
    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
    ));
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.stage1EmptyTitle), findsOneWidget);
    expect(find.text(OrdersLabels.stage1EmptyBody), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.text(VN.addProduct), findsOneWidget);
  });

  testWidgets('Stage1ProductSelectionScreen shows selected items list when items present (AC-6)',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: const OrderWizardData(),
      items: [
        DraftOrderItem(
          product: const Product(
            id: 1,
            name: 'Bánh mì',
            category: 'banh_mi',
            basePrice: 15000,
          ),
          quantity: 2,
        ),
        DraftOrderItem(
          product: const Product(
            id: 2,
            name: 'Bánh kem',
            category: 'banh_kem',
            basePrice: 200000,
          ),
          quantity: 1,
        ),
      ],
    );
    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      state: testState,
    ));
    await tester.pumpAndSettle();

    expect(find.text(OrdersLabels.selectedProducts), findsOneWidget);
    expect(find.text('Bánh mì'), findsOneWidget);
    expect(find.text('Bánh kem'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('Stage3DeliveryOptionsScreen shows address fields for door delivery',
      (tester) async {
    const testState = OrderCreateState(
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

  testWidgets('Stage2CustomerInfoScreen shows Stage 1 product summary',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: const OrderWizardData(
        customerName: 'Test Customer',
        customerPhone: '0123456789',
      ),
      source: 'Online',
      items: [
        DraftOrderItem(
          product: const Product(
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
      Stage2CustomerInfoScreen(onBack: () {}, onContinue: () {}),
      state: testState,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tóm tắt bước trước'), findsOneWidget);
    expect(find.text('Sản phẩm'), findsWidgets);
    expect(find.text('Test Cake x2 — 300.000đ'), findsOneWidget);
  });

  testWidgets('Stage3DeliveryOptionsScreen shows Stage 1+2 summary',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: const OrderWizardData(
        customerName: 'Nguyen Van A',
        customerPhone: '0987654321',
        deliveryType: 'pickup',
      ),
      source: 'Online',
      items: [
        DraftOrderItem(
          product: const Product(
            id: 2,
            name: 'Bánh mì',
            category: 'banh_mi',
            basePrice: 15000,
          ),
          quantity: 3,
        ),
      ],
    );

    await tester.pumpWidget(buildTestWidget(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: testState,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tóm tắt bước trước'), findsOneWidget);
    expect(find.text('Bánh mì x3 — 45.000đ'), findsOneWidget);
    expect(find.text('Nguyen Van A'), findsOneWidget);
    expect(find.text('0987654321'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('Stage4ReviewScreen shows all-stage summary card',
      (tester) async {
    final testState = OrderCreateState(
      wizardData: const OrderWizardData(
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
          product: const Product(
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
    await tester.pumpAndSettle();

    expect(find.text('Tóm tắt đơn hàng'), findsOneWidget);
    expect(find.text('Tóm tắt bước trước'), findsOneWidget);
    expect(find.text('Test Cake x2 — 300.000đ'), findsOneWidget);
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('Giao tận nơi'), findsOneWidget);
    expect(find.text('123 Test St'), findsOneWidget);
    expect(find.text('20.000đ'), findsOneWidget);
    expect(find.text('Tạo đơn hàng'), findsOneWidget);
  });

  testWidgets('AC-2/AC-3: (+) opens ProductPickerPage; tapping product returns item to Stage 1 (expanded)',
      (tester) async {
    final products = [
      const Product(
        id: 10,
        name: 'Bánh mì',
        category: 'banh_mi',
        basePrice: 15000,
        active: 1,
      ),
    ];
    const categories = [
      Category(id: 1, slug: 'banh_mi', name: 'Bánh mì', codePrefix: 'BM', active: 1),
    ];

    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      products: products,
      categories: categories,
    ));
    await tester.pumpAndSettle();

    // AC-1 precondition: empty state with (+) button.
    expect(find.text(OrdersLabels.stage1EmptyTitle), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);

    // Tap the (+) filled button to open the picker.
    await tester.tap(find.text(VN.addProduct));
    await tester.pumpAndSettle();

    // AC-2: ProductPickerPage is shown full-screen with the product grid.
    expect(find.byType(ProductPickerPage), findsOneWidget);
    expect(find.text('Bánh mì'), findsWidgets);

    // AC-3: Tap the product -> picker closes -> item appears in Stage 1 list.
    await tester.tap(find.text('Bánh mì').first);
    await tester.pumpAndSettle();

    expect(find.byType(ProductPickerPage), findsNothing);
    expect(find.text(OrdersLabels.selectedProducts), findsOneWidget);
    // New item card is expanded by default (ExpandableItemCard._expanded = true).
    expect(find.text('Bánh mì'), findsWidgets);
  });
}
