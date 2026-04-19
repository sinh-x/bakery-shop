import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/product.dart';

/// A single item in the POS cart.
class PosCartItem {
  PosCartItem({
    required this.product,
    required this.quantity,
    this.isGift = false,
  });

  final Product product;
  int quantity;
  final bool isGift;

  double get total => product.basePrice * quantity;
}

/// The state of the POS cart.
class PosCartState {
  PosCartState({this.items = const []});

  final List<PosCartItem> items;

  double get total =>
      items.where((i) => !i.isGift).fold(0, (sum, i) => sum + i.total);
}

/// POS cart notifier for counter sales (Phase 2B).
class PosCartNotifier extends Notifier<PosCartState> {
  @override
  PosCartState build() => PosCartState();

  /// Gift extras auto-added when a tang_kem product >= 100k is added.
  static const _giftExtras = [
    ('Nến', 5000.0),
    ('Đĩa muỗng', 10000.0),
    ('Nón', 5000.0),
  ];

  void addItem(Product product) {
    final items = List<PosCartItem>.from(state.items);

    // Check if product already in cart (not as gift)
    final existing = items.where(
      (i) => i.product.id == product.id && !i.isGift,
    ).firstOrNull;

    if (existing != null) {
      existing.quantity += 1;
    } else {
      items.add(PosCartItem(product: product, quantity: 1));
    }

    // Auto-gift: if tang_kem + total >= 100k, add gift extras
    if (product.attributes['tang_kem']?.toString() == 'true') {
      final qualified = items
          .where((i) =>
              i.product.attributes['tang_kem']?.toString() == 'true' &&
              !i.isGift)
          .fold<double>(0, (sum, i) => sum + i.total);

      if (qualified >= 100000) {
        for (final (name, price) in _giftExtras) {
          final existingGift = items.where(
            (i) => i.product.name == name && i.isGift,
          ).firstOrNull;
          if (existingGift != null) {
            existingGift.quantity += 1;
          } else {
            items.add(PosCartItem(
              product: Product(
                id: -1,
                name: name,
                basePrice: price,
                attributes: const {'_gift': 'true'},
              ),
              quantity: 1,
              isGift: true,
            ));
          }
        }
      }
    }

    state = PosCartState(items: items);
  }

  void removeItem(int productId) {
    state = PosCartState(
      items: state.items.where((i) => i.product.id != productId).toList(),
    );
  }

  void updateQuantity(int productId, int qty) {
    if (qty <= 0) {
      removeItem(productId);
      return;
    }
    final items = List<PosCartItem>.from(state.items);
    final item = items.where((i) => i.product.id == productId).firstOrNull;
    if (item != null) {
      item.quantity = qty;
    }
    state = PosCartState(items: items);
  }

  void clearCart() {
    state = PosCartState();
  }
}

final posCartProvider = NotifierProvider<PosCartNotifier, PosCartState>(
  PosCartNotifier.new,
);
