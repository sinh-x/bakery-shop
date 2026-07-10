import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/shared/gift_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [CustomerService] that returns a canned [Customer] for
/// [getCustomer] and records the last requested id.
class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customer) : super(Dio());

  final Customer _customer;
  int? lastRequestedId;

  @override
  Future<Customer> getCustomer(int id) async {
    lastRequestedId = id;
    return _customer;
  }
}

/// Fake [ProductService] used to feed the `phuKienProductsProvider` with
/// catalog products so [checkAutoGift] can resolve gift extras by name.
class _FakeProductService extends ProductService {
  _FakeProductService(this._phuKienProducts) : super(Dio());

  final List<Product> _phuKienProducts;

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    if (category == 'phu_kien') return List<Product>.from(_phuKienProducts);
    return const <Product>[];
  }
}

Product _tangKemProduct({
  required int id,
  required String name,
  required double basePrice,
}) {
  return Product(
    id: id,
    name: name,
    category: 'banh_kem',
    basePrice: basePrice,
    attributes: const {'tang_kem': 'true'},
  );
}

Product _phuKienProduct({
  required int id,
  required String name,
  required double basePrice,
}) {
  return Product(
    id: id,
    name: name,
    category: 'phu_kien',
    basePrice: basePrice,
  );
}

void main() {
  group('OrderCreateStateNotifier.checkAutoGift', () {
    test('adds gift extras when tang_kem total >= giftThreshold', () async {
      final giftProducts = <Product>[
        _phuKienProduct(id: 101, name: 'Nến', basePrice: 5000),
        _phuKienProduct(id: 102, name: 'Đĩa muỗng', basePrice: 10000),
        _phuKienProduct(id: 103, name: 'Nón', basePrice: 5000),
      ];
      final fakeProductService = _FakeProductService(giftProducts);
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(fakeProductService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);

      final qualifying = _tangKemProduct(
        id: 1,
        name: 'Bánh kem sinh nhật',
        basePrice: GiftConfig.giftThreshold,
      );
      notifier.updateItems([
        DraftOrderItem(product: qualifying, quantity: 1),
      ]);

      await notifier.checkAutoGift();

      final state = container.read(orderCreateStateProvider);
      final gifts = state.items.where((i) => i.isGift).toList();
      expect(gifts, hasLength(GiftConfig.giftExtras.length));
      for (final gift in gifts) {
        final configured = GiftConfig.giftExtras.firstWhere(
          (entry) => entry.$1.trim().toLowerCase() ==
              gift.product.name.trim().toLowerCase(),
        );
        expect(gift.unitPrice, configured.$2);
        expect(gift.quantity, 1);
      }
    });

    test('does NOT add gifts when tang_kem total < giftThreshold', () async {
      final fakeProductService = _FakeProductService(const <Product>[]);
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(fakeProductService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);

      final qualifying = _tangKemProduct(
        id: 1,
        name: 'Bánh kem nhỏ',
        basePrice: GiftConfig.giftThreshold - 1,
      );
      notifier.updateItems([
        DraftOrderItem(product: qualifying, quantity: 1),
      ]);

      await notifier.checkAutoGift();

      final state = container.read(orderCreateStateProvider);
      expect(state.items.where((i) => i.isGift), isEmpty);
    });

    test('increments existing gift quantity instead of duplicating', () async {
      final giftProducts = <Product>[
        _phuKienProduct(id: 101, name: 'Nến', basePrice: 5000),
      ];
      final fakeProductService = _FakeProductService(giftProducts);
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(fakeProductService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);

      final qualifying = _tangKemProduct(
        id: 1,
        name: 'Bánh kem sinh nhật',
        basePrice: GiftConfig.giftThreshold,
      );
      notifier.updateItems([
        DraftOrderItem(product: qualifying, quantity: 1),
      ]);

      await notifier.checkAutoGift();
      await notifier.checkAutoGift();

      final state = container.read(orderCreateStateProvider);
      final nenGifts = state.items
          .where((i) => i.isGift && i.product.id == 101)
          .toList();
      expect(nenGifts, hasLength(1));
      expect(nenGifts.first.quantity, 2);
    });

    test('no-op when no tang_kem products present', () async {
      final fakeProductService = _FakeProductService(const <Product>[]);
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(fakeProductService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);

      const plainProduct = Product(
        id: 5,
        name: 'Bánh mì',
        category: 'bread',
        basePrice: 50000,
      );
      notifier.updateItems([
        DraftOrderItem(product: plainProduct, quantity: 2),
      ]);

      await notifier.checkAutoGift();

      final state = container.read(orderCreateStateProvider);
      expect(state.items, hasLength(1));
      expect(state.items.where((i) => i.isGift), isEmpty);
    });
  });

  group('OrderCreateStateNotifier.addCatalogExtra', () {
    test('adds a new extra item when no matching extra exists', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      final product = _phuKienProduct(id: 10, name: 'Nến', basePrice: 5000);

      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);

      final state = container.read(orderCreateStateProvider);
      expect(state.items, hasLength(1));
      final item = state.items.single;
      expect(item.product.id, 10);
      expect(item.isExtra, isTrue);
      expect(item.isGift, isFalse);
      expect(item.quantity, 1);
      expect(item.unitPrice, 5000);
    });

    test('increments quantity when matching extra already exists', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      final product = _phuKienProduct(id: 10, name: 'Nến', basePrice: 5000);

      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);
      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);
      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);

      final state = container.read(orderCreateStateProvider);
      expect(state.items, hasLength(1));
      expect(state.items.single.quantity, 3);
    });

    test('treats same product with different price as separate items', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      final product = _phuKienProduct(id: 10, name: 'Nến', basePrice: 5000);

      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);
      notifier.addCatalogExtra(product: product, customUnitPrice: 7000);

      final state = container.read(orderCreateStateProvider);
      expect(state.items, hasLength(2));
    });

    test('separates gift extras from non-gift extras', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      final product = _phuKienProduct(id: 10, name: 'Nến', basePrice: 5000);

      notifier.addCatalogExtra(product: product, customUnitPrice: 5000);
      notifier.addCatalogExtra(
        product: product,
        customUnitPrice: 5000,
        isGift: true,
      );

      final state = container.read(orderCreateStateProvider);
      expect(state.items, hasLength(2));
      expect(
        state.items.where((i) => !i.isGift && i.product.id == 10),
        hasLength(1),
      );
      expect(
        state.items.where((i) => i.isGift && i.product.id == 10),
        hasLength(1),
      );
    });
  });

  group('OrderCreateStateNotifier.canNavigateToStage', () {
    test('allows navigating to current or earlier stage', () {
      const state = OrderCreateState(
        wizardData: OrderWizardData(),
        currentStage: 3,
      );
      expect(state.canNavigateToStage(1), isTrue);
      expect(state.canNavigateToStage(2), isTrue);
      expect(state.canNavigateToStage(3), isTrue);
    });

    test('blocks stage >=2 when items empty', () {
      const state = OrderCreateState(
        wizardData: OrderWizardData(),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(2), isFalse);
      expect(state.canNavigateToStage(3), isFalse);
      expect(state.canNavigateToStage(4), isFalse);
    });

    test('allows stage 2 when items present but blocks stage 3 without customer name', () {
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(2), isTrue);
      expect(state.canNavigateToStage(3), isFalse);
    });

    test('allows stage 3 when items and customer name present', () {
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(customerName: 'Sinh'),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(3), isTrue);
    });

    test('blocks stage 4 when delivery requires address but it is empty', () {
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(
          customerName: 'Sinh',
          deliveryType: 'door',
          deliveryAddress: '',
        ),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(4), isFalse);
    });

    test('allows stage 4 when delivery address is filled', () {
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(
          customerName: 'Sinh',
          deliveryType: 'door',
          deliveryAddress: '123 Lê Lợi',
        ),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(4), isTrue);
    });

    test('allows stage 4 for pickup delivery without address requirement', () {
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(
          customerName: 'Sinh',
          deliveryType: 'pickup',
        ),
        currentStage: 1,
      );
      expect(state.canNavigateToStage(4), isTrue);
    });
  });

  group('OrderCreateStateNotifier.restoreCustomerFromDraft', () {
    test('restores customer into wizardData', () async {
      const customer = Customer(
        id: 42,
        name: 'Mai',
        phone: '0901234567',
      );
      final fakeService = _FakeCustomerService(customer);
      final container = ProviderContainer(
        overrides: [
          customerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      await notifier.restoreCustomerFromDraft(42);

      expect(fakeService.lastRequestedId, 42);
      final state = container.read(orderCreateStateProvider);
      expect(state.wizardData.selectedCustomer?.id, 42);
      expect(state.wizardData.customerName, 'Mai');
      expect(state.wizardData.customerPhone, '0901234567');
    });

    test('swallows error and leaves state unchanged', () async {
      final container = ProviderContainer(
        overrides: [
          customerServiceProvider.overrideWithValue(_ThrowingCustomerService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      final stateBefore = container.read(orderCreateStateProvider);

      await notifier.restoreCustomerFromDraft(99);

      final stateAfter = container.read(orderCreateStateProvider);
      expect(stateAfter.wizardData.selectedCustomer,
          stateBefore.wizardData.selectedCustomer);
      expect(stateAfter.wizardData.customerName,
          stateBefore.wizardData.customerName);
    });
  });

  group('OrderCreateStateNotifier.reset', () {
    test('clears items, wizardData, and restores default due date/time', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      const product = Product(id: 1, name: 'Bánh', basePrice: 10000);
      notifier.updateItems([DraftOrderItem(product: product)]);
      notifier.updateWizardData(
        const OrderWizardData(customerName: 'Sinh', deliveryType: 'door'),
      );
      notifier.updateSource('Zalo');
      notifier.goToStage(3);

      notifier.reset();

      final state = container.read(orderCreateStateProvider);
      expect(state.items, isEmpty);
      expect(state.wizardData.customerName, isEmpty);
      expect(state.wizardData.deliveryType, 'pickup');
      expect(state.source, isEmpty);
      expect(state.currentStage, 1);
      expect(state.selectedCategorySlug, isNull);
      expect(state.dueDate, isNotNull);
      expect(state.dueTime, isNotNull);
    });

    test('reset default due time is rounded to 30-min slot', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(orderCreateStateProvider.notifier);
      notifier.reset();

      final state = container.read(orderCreateStateProvider);
      expect(state.dueTime!.minute == 0 || state.dueTime!.minute == 30, isTrue);
    });
  });
}

/// CustomerService fake that always throws on [getCustomer] — used to test
/// error swallowing in [restoreCustomerFromDraft].
class _ThrowingCustomerService extends CustomerService {
  _ThrowingCustomerService() : super(Dio());

  @override
  Future<Customer> getCustomer(int id) async {
    throw Exception('network down');
  }
}