import '../../data/models/price_chip.dart';
import '../../data/models/product.dart';

int baseStockQty(Product product) {
  final totalStock = product.stockQty ?? 0;
  final chipStock = product.priceChips.fold<int>(
    0,
    (sum, chip) => sum + (chip.stockQty ?? 0),
  );
  final baseStock = totalStock - chipStock;
  return baseStock > 0 ? baseStock : 0;
}

int? backendChipIdForSelection(Product product, PriceChip chip) {
  if (chip.price == product.basePrice) return null;
  return chip.id;
}

int chipDisplayStockQty(Product product, PriceChip chip) {
  final chipStock = chip.stockQty ?? 0;
  if (backendChipIdForSelection(product, chip) == null) {
    return chipStock + baseStockQty(product);
  }
  return chipStock;
}