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
}
