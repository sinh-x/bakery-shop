import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/extras_section.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/stage1_product_selection_screen.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/gift_config.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedOrderCreateStateNotifier extends OrderCreateStateNotifier {
  final OrderCreateState initial;
  _FixedOrderCreateStateNotifier(this.initial);

  @override
  OrderCreateState build() => initial;
}

void main() {
  ProviderContainer containerWithProducts(List<Product> products,
      {OrderCreateState? state}) {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith((ref) async => products),
        if (state != null)
          orderCreateStateProvider.overrideWith(
            () => _FixedOrderCreateStateNotifier(state),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrapWidget(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('AC-7: extras/gifts available in item detail form', () {
    testWidgets(
        'Stage1ProductSelectionScreen renders ExtrasSection with phu_kien chips',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const phuKienProducts = <Product>[
        Product(
          id: 201,
          name: 'Nến',
          category: 'phu_kien',
          active: 1,
          basePrice: 5000,
        ),
        Product(
          id: 202,
          name: 'Đĩa muỗng',
          category: 'phu_kien',
          active: 1,
          basePrice: 10000,
        ),
      ];
      final state = OrderCreateState(
        wizardData: const OrderWizardData(),
        items: [
          DraftOrderItem(
            product: const Product(
              id: 10,
              name: 'Bánh kem',
              category: 'banh_kem',
              basePrice: 200000,
            ),
            quantity: 1,
          ),
        ],
      );
      final container = containerWithProducts(phuKienProducts, state: state);

      await tester.pumpWidget(
        wrapWidget(container, const Stage1ProductSelectionScreen(onContinue: _noop)),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.addExtra), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(2));
      expect(find.text('Nến (5.000đ)'), findsOneWidget);
      expect(find.text('Đĩa muỗng (10.000đ)'), findsOneWidget);
    });

    testWidgets(
        'tapping extra chip opens price dialog; confirming base price adds paid extra',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const phuKienProducts = <Product>[
        Product(
          id: 201,
          name: 'Nến',
          category: 'phu_kien',
          active: 1,
          basePrice: 5000,
        ),
      ];
      final state = OrderCreateState(
        wizardData: const OrderWizardData(),
        items: [
          DraftOrderItem(
            product: const Product(
              id: 10,
              name: 'Bánh kem',
              category: 'banh_kem',
              basePrice: 200000,
            ),
            quantity: 1,
          ),
        ],
      );
      final container = containerWithProducts(phuKienProducts, state: state);

      await tester.pumpWidget(
        wrapWidget(container, const Stage1ProductSelectionScreen(onContinue: _noop)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nến (5.000đ)'));
      await tester.pumpAndSettle();

      expect(find.byType(CatalogExtraPriceDialog), findsOneWidget);
      expect(find.textContaining(VN.giaCoSo), findsOneWidget);

      await tester.tap(find.text(VN.xacNhan));
      await tester.pumpAndSettle();

      final items = container.read(orderCreateStateProvider).items;
      final extras = items.where((i) => i.isExtra).toList();
      expect(extras, hasLength(1));
      expect(extras.single.isGift, isFalse);
      expect(extras.single.product.name, 'Nến');
      expect(extras.single.quantity, 1);
    });

    testWidgets('addCatalogExtra increments qty for matching existing extra',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const phuKienProducts = <Product>[
        Product(
          id: 201,
          name: 'Nến',
          category: 'phu_kien',
          active: 1,
          basePrice: 5000,
        ),
      ];
      final state = OrderCreateState(
        wizardData: const OrderWizardData(),
        items: [
          DraftOrderItem(
            product: const Product(
              id: 10,
              name: 'Bánh kem',
              category: 'banh_kem',
              basePrice: 200000,
            ),
            quantity: 1,
          ),
          createCatalogExtraItem(
            product: const Product(
              id: 201,
              name: 'Nến',
              category: 'phu_kien',
              basePrice: 5000,
            ),
          ),
        ],
      );
      final container = containerWithProducts(phuKienProducts, state: state);

      await tester.pumpWidget(
        wrapWidget(container, const Stage1ProductSelectionScreen(onContinue: _noop)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nến (5.000đ)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.xacNhan));
      await tester.pumpAndSettle();

      final extras = container
          .read(orderCreateStateProvider)
          .items
          .where((i) => i.isExtra)
          .toList();
      expect(extras, hasLength(1));
      expect(extras.single.quantity, 2);
    });
  });

  group('Phase 5: auto-gift triggers on tang_kem threshold', () {
    test('checkAutoGift adds gift extras when tang_kem total >= threshold',
        () async {
      const phuKienProducts = <Product>[
        Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
        Product(id: 202, name: 'Đĩa muỗng', category: 'phu_kien', active: 1),
        Product(id: 203, name: 'Nón', category: 'phu_kien', active: 1),
      ];
      final container = containerWithProducts(phuKienProducts);
      await container.read(phuKienProductsProvider.future);

      container.read(orderCreateStateProvider.notifier).updateItems([
        DraftOrderItem(
          product: const Product(
            id: 10,
            name: 'Bánh kem tang kem',
            category: 'banh_kem',
            basePrice: GiftConfig.giftThreshold,
            attributes: {'tang_kem': 'true'},
          ),
          quantity: 1,
        ),
      ]);

      container.read(orderCreateStateProvider.notifier).checkAutoGift();

      final items = container.read(orderCreateStateProvider).items;
      final gifts = items.where((i) => i.isGift).toList();
      expect(gifts, hasLength(3));
      final giftNames = gifts.map((g) => g.product.name).toSet();
      expect(giftNames, containsAll(<String>['Nến', 'Đĩa muỗng', 'Nón']));
      for (final g in gifts) {
        expect(g.isExtra, isTrue);
      }
    });

    test('checkAutoGift does NOT trigger below threshold', () async {
      const phuKienProducts = <Product>[
        Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
      ];
      final container = containerWithProducts(phuKienProducts);
      await container.read(phuKienProductsProvider.future);

      container.read(orderCreateStateProvider.notifier).updateItems([
        DraftOrderItem(
          product: const Product(
            id: 10,
            name: 'Bánh kem tang kem',
            category: 'banh_kem',
            basePrice: GiftConfig.giftThreshold - 1,
            attributes: {'tang_kem': 'true'},
          ),
          quantity: 1,
        ),
      ]);

      container.read(orderCreateStateProvider.notifier).checkAutoGift();

      final items = container.read(orderCreateStateProvider).items;
      final gifts = items.where((i) => i.isGift).toList();
      expect(gifts, isEmpty);
    });

    test('checkAutoGift does NOT trigger without tang_kem product', () async {
      const phuKienProducts = <Product>[
        Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
      ];
      final container = containerWithProducts(phuKienProducts);
      await container.read(phuKienProductsProvider.future);

      container.read(orderCreateStateProvider.notifier).updateItems([
        DraftOrderItem(
          product: const Product(
            id: 10,
            name: 'Bánh kem thường',
            category: 'banh_kem',
            basePrice: GiftConfig.giftThreshold * 2,
          ),
          quantity: 1,
        ),
      ]);

      container.read(orderCreateStateProvider.notifier).checkAutoGift();

      final gifts = container
          .read(orderCreateStateProvider)
          .items
          .where((i) => i.isGift)
          .toList();
      expect(gifts, isEmpty);
    });

    test('checkAutoGift increments existing gift quantity (no duplicate)',
        () async {
      const giftProduct = Product(
        id: 201,
        name: 'Nến',
        category: 'phu_kien',
        active: 1,
      );
      const phuKienProducts = <Product>[giftProduct];
      final container = containerWithProducts(phuKienProducts);
      await container.read(phuKienProductsProvider.future);

      final existingGift = createCatalogExtraItem(
        product: giftProduct,
        isGift: true,
        customUnitPrice: 5000,
      );
      container.read(orderCreateStateProvider.notifier).updateItems([
        DraftOrderItem(
          product: const Product(
            id: 10,
            name: 'Bánh kem tang kem',
            category: 'banh_kem',
            basePrice: GiftConfig.giftThreshold,
            attributes: {'tang_kem': 'true'},
          ),
          quantity: 1,
        ),
        existingGift,
      ]);

      container.read(orderCreateStateProvider.notifier).checkAutoGift();

      final items = container.read(orderCreateStateProvider).items;
      final gifts = items.where((i) => i.isGift && i.product.name == 'Nến').toList();
      expect(gifts, hasLength(1));
      expect(gifts.single.quantity, 2);
    });

    test('checkAutoGift skips unmatched configured names', () async {
      const phuKienProducts = <Product>[
        Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
      ];
      final container = containerWithProducts(phuKienProducts);
      await container.read(phuKienProductsProvider.future);

      container.read(orderCreateStateProvider.notifier).updateItems([
        DraftOrderItem(
          product: const Product(
            id: 10,
            name: 'Bánh kem tang kem',
            category: 'banh_kem',
            basePrice: GiftConfig.giftThreshold,
            attributes: {'tang_kem': 'true'},
          ),
          quantity: 1,
        ),
      ]);

      container.read(orderCreateStateProvider.notifier).checkAutoGift();

      final gifts = container
          .read(orderCreateStateProvider)
          .items
          .where((i) => i.isGift)
          .toList();
      expect(gifts, hasLength(1));
      expect(gifts.single.product.name, 'Nến');
    });
  });
}

void _noop() {}