import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

void main() {
  Product tangKemProduct() {
    return const Product(
      id: 10,
      name: 'Banh kem tang qua',
      category: 'banh_kem',
      basePrice: 120000,
      attributes: {'tang_kem': 'true'},
    );
  }

  test('auto-gift resolves configured names to phu_kien products', () async {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith(
          (ref) => Future.value(
            const <Product>[
              Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
              Product(id: 202, name: '  đĩa MUỖNG  ', category: 'phu_kien', active: 1),
              Product(id: 203, name: 'Nón', category: 'phu_kien', active: 1),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(phuKienProductsProvider.future);
    container.read(posCartProvider.notifier).addItem(tangKemProduct());

    final state = container.read(posCartProvider);
    final giftItems = state.items.where((item) => item.isGift).toList();

    expect(giftItems, hasLength(3));
    expect(giftItems.map((item) => item.product.id), containsAll(<int>[201, 202, 203]));
    expect(giftItems.every((item) => item.product.attributes['_gift'] == 'true'), isTrue);
  });

  test('auto-gift skips unmatched configured names', () async {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith(
          (ref) => Future.value(
            const <Product>[
              Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(phuKienProductsProvider.future);
    container.read(posCartProvider.notifier).addItem(tangKemProduct());

    final state = container.read(posCartProvider);
    final giftItems = state.items.where((item) => item.isGift).toList();
    expect(giftItems, hasLength(1));
    expect(giftItems.single.product.name, 'Nến');
  });

  test(
      'replaceCart prunes stale gifts when qualifying item quantity drops below threshold (Mn6)',
      () async {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith(
          (ref) => Future.value(
            const <Product>[
              Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
              Product(id: 202, name: 'Đĩa muỗng', category: 'phu_kien', active: 1),
              Product(id: 203, name: 'Nón', category: 'phu_kien', active: 1),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(phuKienProductsProvider.future);

    // Build a cart at the threshold (120000 >= 100000) with gifts attached.
    final product = tangKemProduct();
    final qualifyingCart = [
      PosCartItem(product: product, quantity: 1),
      PosCartItem(
        product: const Product(
          id: 201,
          name: 'Nến',
          category: 'phu_kien',
          basePrice: 5000,
          active: 1,
        ),
        quantity: 1,
        isGift: true,
      ),
    ];
    container.read(posCartProvider.notifier).replaceCart(qualifyingCart);
    expect(
      container.read(posCartProvider).items.where((i) => i.isGift),
      isNotEmpty,
      reason: 'sanity: at-threshold cart keeps its gifts',
    );

    // Now reduce the qualifying item quantity below the threshold (1 cake at
    // 120000 -> reduce to a quantity that totals < 100000 is impossible with
    // qty=1, so drop the qualifying item entirely and keep only the stale gift.
    final reducedCart = [
      PosCartItem(product: product, quantity: 0),
    ];
    container.read(posCartProvider.notifier).replaceCart(reducedCart);

    final state = container.read(posCartProvider);
    expect(
      state.items.where((i) => i.isGift),
      isEmpty,
      reason: 'Mn6: stale gifts must be pruned when the qualifying item no '
          'longer meets the gift threshold',
    );
  });

  test(
      'replaceCart re-adds gifts when the qualifying total still meets the threshold (Mn6)',
      () async {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith(
          (ref) => Future.value(
            const <Product>[
              Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(phuKienProductsProvider.future);

    final product = tangKemProduct();
    // 1 cake at 120000 >= 100000 threshold, no pre-existing gifts.
    container
        .read(posCartProvider.notifier)
        .replaceCart([PosCartItem(product: product, quantity: 1)]);

    final state = container.read(posCartProvider);
    expect(state.items.where((i) => i.isGift), isNotEmpty,
        reason: 'Mn6: replaceCart must recompute gifts for qualifying carts');
  });

  test(
      'addItem increments an existing gift while replaceCart preserves its quantity (Mn7)',
      () async {
    final container = ProviderContainer(
      overrides: [
        phuKienProductsProvider.overrideWith(
          (ref) => Future.value(
            const <Product>[
              Product(id: 201, name: 'Nến', category: 'phu_kien', active: 1),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(phuKienProductsProvider.future);

    final product = tangKemProduct();
    final notifier = container.read(posCartProvider.notifier);

    // First qualifying add creates the gift with quantity 1.
    notifier.addItem(product);
    int giftQuantity() =>
        container
            .read(posCartProvider)
            .items
            .where((i) => i.isGift)
            .fold(0, (sum, i) => sum + i.quantity);
    expect(giftQuantity(), 1, reason: 'sanity: first add creates one gift');

    // Second qualifying addItem must INCREMENT the existing gift (Mn7).
    notifier.addItem(product);
    expect(giftQuantity(), 2,
        reason: 'Mn7: addItem increments an existing gift quantity');

    // replaceCart of the same qualifying contents must PRESERVE the gift
    // quantity, not increment it again (Mn7).
    final cart = container.read(posCartProvider).items;
    notifier.replaceCart(cart);
    expect(giftQuantity(), 2,
        reason: 'Mn7: replaceCart preserves the existing gift quantity');
  });

  group('replaceCart preserves lossless fields (B1a)', () {
    test('replaceCart preserves notes and pendingPhotos', () {
      final product = tangKemProduct();
      final items = [
        PosCartItem(
          product: product,
          quantity: 1,
          notes: 'Không đường',
          pendingPhotos: <XFile>[],
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          phuKienProductsProvider.overrideWith(
            (ref) => Future.value(const <Product>[]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(posCartProvider.notifier).replaceCart(items);
      final state = container.read(posCartProvider);
      expect(state.items.single.notes, 'Không đường');
      expect(state.items.single.pendingPhotos, isEmpty);
    });
  });

  group('B1a PosCartItem lossless round-trip', () {
    test('round-trip preserves notes, photos, chip, and useInventory', () {
      final item = PosCartItem(
        product: tangKemProduct(),
        quantity: 2,
        isGift: false,
        useInventory: false,
        selectedPrice: 130000,
        selectedChipId: 5,
        selectedChipLabel: 'Lớn',
        notes: 'Không đường',
        pendingPhotos: <XFile>[],
      );

      expect(item.notes, 'Không đường');
      expect(item.pendingPhotos, isEmpty);
      expect(item.selectedChipId, 5);
      expect(item.selectedChipLabel, 'Lớn');
      expect(item.selectedPrice, 130000);
      expect(item.useInventory, isFalse);
      expect(item.quantity, 2);
    });

    test('notes and photos do not affect lineKey', () {
      final a = PosCartItem(product: tangKemProduct(), quantity: 1, notes: 'Ghi chú A');
      final b = PosCartItem(product: tangKemProduct(), quantity: 1, notes: 'Ghi chú B');
      expect(a.lineKey, b.lineKey);
    });

    test('default notes is empty string', () {
      final item = PosCartItem(product: tangKemProduct(), quantity: 1);
      expect(item.notes, '');
    });

    test('default pendingPhotos is empty list', () {
      final item = PosCartItem(product: tangKemProduct(), quantity: 1);
      expect(item.pendingPhotos, isEmpty);
    });
  });
}
