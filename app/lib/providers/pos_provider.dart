import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/models/product.dart';
import '../providers/products_provider.dart';
import '../shared/gift_config.dart';

/// A single item in the POS cart.
class PosCartItem {
  PosCartItem({
    required this.product,
    required this.quantity,
    this.isGift = false,
    this.useInventory = true,
    this.selectedPrice,
    this.selectedChipId,
    this.selectedChipLabel,
  });

  final Product product;
  int quantity;
  final bool isGift;
  final bool useInventory;
  final double? selectedPrice;
  final int? selectedChipId;
  final String? selectedChipLabel;

  String get lineKey {
    final option = selectedChipId != null ? 'chip:$selectedChipId' : 'base';
    return '${product.id}:$option:inventory:${useInventory ? 1 : 0}';
  }

  double get unitPrice => selectedPrice ?? product.basePrice;

  double get total => unitPrice * quantity;
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

  void addItem(
    Product product, {
    double? selectedPrice,
    int? selectedChipId,
    String? selectedChipLabel,
    bool useInventory = true,
  }) {
    final items = List<PosCartItem>.from(state.items);
    final option = selectedChipId != null ? 'chip:$selectedChipId' : 'base';
    final lineKey = '${product.id}:$option:inventory:${useInventory ? 1 : 0}';

    // Check if same product + same chip selection is already in cart.
    final existing = items
        .where((i) => i.lineKey == lineKey && !i.isGift)
        .firstOrNull;

    if (existing != null) {
      existing.quantity += 1;
    } else {
      items.add(
        PosCartItem(
          product: product,
          quantity: 1,
          useInventory: useInventory,
          selectedPrice: selectedPrice,
          selectedChipId: selectedChipId,
          selectedChipLabel: selectedChipLabel,
        ),
      );
    }

    // Auto-gift: if tang_kem + total >= threshold, add gift extras
    if (product.attributes['tang_kem']?.toString() == 'true') {
      final qualified = items
          .where(
            (i) =>
                i.product.attributes['tang_kem']?.toString() == 'true' &&
                !i.isGift,
          )
          .fold<double>(0, (sum, i) => sum + i.total);

      if (qualified >= GiftConfig.giftThreshold) {
        final giftCatalog = _giftCatalogByNormalizedName();
        for (final (configuredName, configuredPrice) in GiftConfig.giftExtras) {
          final normalized = _normalizeGiftName(configuredName);
          final giftProduct = giftCatalog[normalized];
          if (giftProduct == null) {
            assert(() {
              debugPrint(
                'pos_provider: unmatched gift config "${configuredName.trim()}" '
                'for active phu_kien products',
              );
              return true;
            }());
            continue;
          }

          final existingGift = items
              .where((i) => i.product.id == giftProduct.id && i.isGift)
              .firstOrNull;
          if (existingGift != null) {
            existingGift.quantity += 1;
            continue;
          }

          items.add(
            PosCartItem(
              product: giftProduct.copyWith(
                basePrice: configuredPrice,
                attributes: {
                  ...giftProduct.attributes,
                  '_gift': 'true',
                },
              ),
              quantity: 1,
              isGift: true,
            ),
          );
        }
      }
    }

    state = PosCartState(items: items);
  }

  void removeItemByLineKey(String lineKey) {
    state = PosCartState(
      items: state.items.where((i) => i.lineKey != lineKey).toList(),
    );
  }

  void updateQuantityByLineKey(String lineKey, int qty) {
    if (qty <= 0) {
      removeItemByLineKey(lineKey);
      return;
    }
    final items = List<PosCartItem>.from(state.items);
    final item = items.where((i) => i.lineKey == lineKey).firstOrNull;
    if (item != null) {
      item.quantity = qty;
    }
    state = PosCartState(items: items);
  }

  void clearCart() {
    state = PosCartState();
  }

  Map<String, Product> _giftCatalogByNormalizedName() {
    final products = ref.read(phuKienProductsProvider).asData?.value ?? const [];
    final byName = <String, Product>{};
    for (final product in products) {
      final normalized = _normalizeGiftName(product.name);
      if (normalized.isNotEmpty) {
        byName.putIfAbsent(normalized, () => product);
      }
    }
    return byName;
  }

  String _normalizeGiftName(String raw) {
    return raw.trim().toLowerCase();
  }
}

final posCartProvider = NotifierProvider<PosCartNotifier, PosCartState>(
  PosCartNotifier.new,
);
