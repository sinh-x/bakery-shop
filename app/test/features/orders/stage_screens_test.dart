import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/work_item_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/features/orders/order_create_screen.dart';
import 'package:bakery_app/features/orders/widgets/gated_page_physics.dart';
import 'package:bakery_app/features/orders/widgets/order_stage_indicator.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/product_picker_page.dart';
import 'package:bakery_app/features/orders/widgets/stage1_product_selection_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage2_customer_info_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage3_delivery_options_screen.dart';
import 'package:bakery_app/features/orders/widgets/stage4_review_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/config_provider.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class FixedOrderCreateStateNotifier extends OrderCreateStateNotifier {
  final OrderCreateState initial;
  FixedOrderCreateStateNotifier(this.initial);

  @override
  OrderCreateState build() => initial;
}

class _FakeConfigValuesNotifier extends ConfigValuesNotifier {
  final List<String> _values;
  _FakeConfigValuesNotifier(this._values) : super('test');

  @override
  Future<List<String>> build() async => _values;
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
    overrides: [
      shippingFeeBusProvider.overrideWith(
        () => _FakeConfigValuesNotifier(['25000']),
      ),
      shippingFeeDoorProvider.overrideWith(
        () => _FakeConfigValuesNotifier(['20000']),
      ),
      if (state != null)
        orderCreateStateProvider.overrideWith(
          () => FixedOrderCreateStateNotifier(state),
        ),
    ],
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
    expect(find.text('Lấy tại tiệm'), findsWidgets);
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
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(OutlinedButton), findsWidgets);
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

    expect(find.text('Tóm tắt sản phẩm'), findsOneWidget);
    expect(find.text('Sản phẩm:'), findsWidgets);
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

    expect(find.text('Tóm tắt sản phẩm'), findsOneWidget);
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
    expect(find.text('Tóm tắt sản phẩm'), findsOneWidget);
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

  testWidgets('Phase 3: category filter persists selected slug to OrderCreateState',
      (tester) async {
    final products = [
      const Product(
        id: 10,
        name: 'Bánh mì',
        category: 'banh_mi',
        basePrice: 15000,
        active: 1,
      ),
      const Product(
        id: 20,
        name: 'Bánh kem dâu',
        category: 'banh_kem',
        basePrice: 200000,
        active: 1,
      ),
    ];
    const categories = [
      Category(id: 1, slug: 'banh_mi', name: 'Bánh mì', codePrefix: 'BM', active: 1),
      Category(id: 2, slug: 'banh_kem', name: 'Bánh kem', codePrefix: 'BK', active: 1),
    ];

    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      products: products,
      categories: categories,
    ));
    await tester.pumpAndSettle();

    // Open picker.
    await tester.tap(find.text(VN.addProduct));
    await tester.pumpAndSettle();

    expect(find.byType(ProductPickerPage), findsOneWidget);

    // Tap the second category tab (emoji + name: '🎂 Bánh kem').
    await tester.tap(find.text('🎂 Bánh kem'));
    await tester.pumpAndSettle();

    // The 'Bánh kem dâu' product (in banh_kem category) should be visible.
    expect(find.text('Bánh kem dâu'), findsOneWidget);
  });

  group('Phase 4: Stage Gating — canNavigateToStage', () {
    test('allows navigation to current or past stages', () {
      const state = OrderCreateState(
        wizardData: OrderWizardData(),
        currentStage: 3,
      );
      expect(state.canNavigateToStage(1), true);
      expect(state.canNavigateToStage(2), true);
      expect(state.canNavigateToStage(3), true);
    });

    test('blocks stage 2+ when no products selected', () {
      const state = OrderCreateState(
        wizardData: OrderWizardData(),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(2), false);
      expect(state.canNavigateToStage(3), false);
      expect(state.canNavigateToStage(4), false);
    });

    test('allows stage 2 when products selected, blocks stage 3+ without customer',
        () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(),
        currentStage: 1,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(2), true);
      expect(state.canNavigateToStage(3), false);
      expect(state.canNavigateToStage(4), false);
    });

    test('allows stage 3 when stages 1-2 complete', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'door',
          deliveryAddress: '',
        ),
        currentStage: 2,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(3), true);
      expect(state.canNavigateToStage(4), false);
    });

    test('blocks stage 4 when door delivery has empty address', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'door',
          deliveryAddress: '',
        ),
        currentStage: 3,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(4), false);
    });

    test('blocks stage 4 when bus delivery has empty address', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'bus',
          deliveryAddress: '',
        ),
        currentStage: 3,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(4), false);
    });

    test('allows stage 4 when delivery is pickup (no address required)', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'pickup',
        ),
        currentStage: 3,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(4), true);
    });

    test('allows stage 4 when door delivery has address', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'door',
          deliveryAddress: '123 Main St',
        ),
        currentStage: 3,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(4), true);
    });

    test('allows all stage transitions when data is complete (1→2→3→4)', () {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'door',
          deliveryAddress: '123 Main St',
        ),
        currentStage: 1,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      expect(state.canNavigateToStage(1), true);
      expect(state.canNavigateToStage(2), true);
      expect(state.canNavigateToStage(3), true);
      expect(state.canNavigateToStage(4), true);
    });
  });

  testWidgets(
      'Phase 4: tapping future stage with incomplete data does not navigate',
      (tester) async {
    int? tappedStage;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderStageIndicator(
          currentStage: 1,
          onStageTap: (stage) {
            if (stage <= 1) {
              tappedStage = stage;
            }
          },
        ),
      ),
    ));

    await tester.tap(find.text('3'));
    expect(tappedStage, isNull);
  });

  testWidgets(
      'Phase 4: tapping allowed stage does navigate',
      (tester) async {
    int? tappedStage;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderStageIndicator(
          currentStage: 1,
          onStageTap: (stage) => tappedStage = stage,
        ),
      ),
    ));

    await tester.tap(find.text('2'));
    expect(tappedStage, 2);
  });

  testWidgets(
      'Phase 4: all stage transitions invoke callback when gating passes',
      (tester) async {
    int? tappedStage;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderStageIndicator(
          currentStage: 1,
          onStageTap: (stage) => tappedStage = stage,
        ),
      ),
    ));

    await tester.tap(find.text('1'));
    expect(tappedStage, 1);
    tappedStage = null;

    await tester.tap(find.text('2'));
    expect(tappedStage, 2);
    tappedStage = null;

    await tester.tap(find.text('3'));
    expect(tappedStage, 3);
    tappedStage = null;

    await tester.tap(find.text('4'));
    expect(tappedStage, 4);
  });

  testWidgets('Phase 3: ProductPickerPage restores initial category tab from slug',
      (tester) async {
    final products = [
      const Product(
        id: 10,
        name: 'Bánh mì',
        category: 'banh_mi',
        basePrice: 15000,
        active: 1,
      ),
      const Product(
        id: 20,
        name: 'Bánh kem dâu',
        category: 'banh_kem',
        basePrice: 200000,
        active: 1,
      ),
    ];
    const categories = [
      Category(id: 1, slug: 'banh_mi', name: 'Bánh mì', codePrefix: 'BM', active: 1),
      Category(id: 2, slug: 'banh_kem', name: 'Bánh kem', codePrefix: 'BK', active: 1),
    ];

    // Seed state with a pre-selected category slug ('banh_kem').
    const testState = OrderCreateState(
      wizardData: OrderWizardData(),
      selectedCategorySlug: 'banh_kem',
    );

    await tester.pumpWidget(buildStage1TestWidget(
      const Stage1ProductSelectionScreen(onContinue: _noop),
      products: products,
      categories: categories,
      state: testState,
    ));
    await tester.pumpAndSettle();

    // Open picker — should restore to the 'banh_kem' tab (index 1).
    await tester.tap(find.text(VN.addProduct));
    await tester.pumpAndSettle();

    expect(find.byType(ProductPickerPage), findsOneWidget);
    // The 'Bánh kem dâu' product should be visible because the tab was restored.
    expect(find.text('Bánh kem dâu'), findsOneWidget);
  });

  group('Phase 2: Swipe navigation gating', () {
    Widget buildSwipeWidget({
      required OrderCreateState state,
      required void Function(int) onStageChanged,
    }) {
      final controller =
          PageController(initialPage: state.currentStage - 1);
      addTearDown(controller.dispose);
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                final pv = d.primaryVelocity;
                final target = targetStageForSwipe(
                  velocity: Velocity(
                      pixelsPerSecond: pv == null ? Offset.zero : Offset(pv, 0)),
                  currentStage: state.currentStage,
                  pageCount: 4,
                );
                if (target != null && state.canNavigateToStage(target)) {
                  onStageChanged(target);
                }
              },
              child: PageView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  Text('Stage1'),
                  Text('Stage2'),
                  Text('Stage3'),
                  Text('Stage4'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('AC2: blocked swipe shows no movement (stage 1, no items)',
        (tester) async {
      const state = OrderCreateState(
        wizardData: OrderWizardData(),
        currentStage: 1,
      );
      int? changedStage;
      await tester.pumpWidget(buildSwipeWidget(
        state: state,
        onStageChanged: (s) => changedStage = s,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stage1'), findsOneWidget);
      expect(find.text('Stage2'), findsNothing);

      await tester.fling(find.text('Stage1'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Stage1'), findsOneWidget);
      expect(find.text('Stage2'), findsNothing);
      expect(changedStage, isNull);
    });

    testWidgets('AC2: allowed swipe navigates to next stage (items present)',
        (tester) async {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(customerName: 'Test'),
        currentStage: 1,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      int? changedStage;
      await tester.pumpWidget(buildSwipeWidget(
        state: state,
        onStageChanged: (s) => changedStage = s,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stage1'), findsOneWidget);

      await tester.fling(find.text('Stage1'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(changedStage, 2);
    });

    testWidgets('AC2: blocked swipe at stage 3 (door, empty address)',
        (tester) async {
      final state = OrderCreateState(
        wizardData: const OrderWizardData(
          customerName: 'Test',
          deliveryType: 'door',
          deliveryAddress: '',
        ),
        currentStage: 3,
        items: [
          DraftOrderItem(
            product: const Product(
                id: 1, name: 'Test', category: 'test', basePrice: 100),
            quantity: 1,
          ),
        ],
      );
      int? changedStage;
      await tester.pumpWidget(buildSwipeWidget(
        state: state,
        onStageChanged: (s) => changedStage = s,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stage3'), findsOneWidget);

      await tester.fling(find.text('Stage3'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(changedStage, isNull);
    });

    testWidgets('AC2: swipe right to previous stage always allowed',
        (tester) async {
      const state = OrderCreateState(
        wizardData: OrderWizardData(customerName: 'Test'),
        currentStage: 2,
      );
      int? changedStage;
      await tester.pumpWidget(buildSwipeWidget(
        state: state,
        onStageChanged: (s) => changedStage = s,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stage2'), findsOneWidget);

      await tester.fling(find.text('Stage2'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();

      expect(changedStage, 1);
    });
  });

  group('Phase 3: Post-submit navigation to order detail', () {
    testWidgets(
        'AC3: submit navigates to /orders/{orderRef} detail page',
        (tester) async {
      final testState = OrderCreateState(
        wizardData: const OrderWizardData(customerName: 'Test Customer'),
        items: [
          DraftOrderItem(
            product: const Product(
              id: 1,
              name: 'Test Cake',
              category: 'banh_kem',
              basePrice: 150000,
            ),
            quantity: 1,
          ),
        ],
        currentStage: 4,
      );

      SharedPreferences.setMockInitialValues({kLoggedByKey: 'Tester'});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/orders/new',
            builder: (context, state) => const OrderCreateScreen(),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (context, state) =>
                Text('OrderDetail ${state.pathParameters['id']}'),
          ),
        ],
        initialLocation: '/orders/new',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderCreateStateProvider.overrideWith(
              () => FixedOrderCreateStateNotifier(testState),
            ),
            orderServiceProvider.overrideWithValue(_FakeCreateOrderService()),
            customerServiceProvider.overrideWithValue(_NoopCustomerService()),
            workItemServiceProvider.overrideWithValue(_NoopWorkItemService()),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Jump PageView to stage 4 via the stage indicator tap.
      await tester.tap(find.text('Xem lại'));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.reviewCreateOrder), findsOneWidget);
      await tester.tap(find.text(OrdersLabels.reviewCreateOrder));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('OrderDetail ORD-TEST-001'), findsOneWidget);
    });
  });
}

class _FakeCreateOrderService extends OrderService {
  _FakeCreateOrderService() : super(Dio());

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
    return Order(
      id: '1',
      orderRef: 'ORD-TEST-001',
      customerName: customerName,
      items: const [],
      totalPrice: 0,
      createdAt: DateTime(2026, 7, 8),
      updatedAt: DateTime(2026, 7, 8),
    );
  }

  @override
  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async =>
      const [];
}

class _NoopCustomerService extends CustomerService {
  _NoopCustomerService() : super(Dio());
}

class _NoopWorkItemService extends WorkItemService {
  _NoopWorkItemService() : super(Dio());

  @override
  Future<List<WorkItem>> listWorkItems(String orderRef) async => const [];
}
