import '../../../data/models/product.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

extension TrungBayProductX on Product? {
  bool get isTrungBay =>
      this?.attributes['trung_bay']?.toString() == 'true';

  String get stockInlineText {
    final qty = this?.stockQty;
    if (qty == null) return VN.stockUnknown;
    return '${VN.stockRemaining}: $qty';
  }
}

extension InventoryChoiceAttributesX on Map<String, dynamic> {
  bool get useInventory => this['useInventory']?.toString() != 'false';
}
