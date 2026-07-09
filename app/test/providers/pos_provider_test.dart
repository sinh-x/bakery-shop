import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
