import '../../../data/models/product.dart';
import 'package:bakery_app/shared/labels/orders.dart';

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
  bool get useInventory {
    final raw = this['useInventory'];
    if (raw is bool) return raw;
    return raw?.toString().toLowerCase() == 'true';
  }
}
