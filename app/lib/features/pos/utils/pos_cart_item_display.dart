import '../../../providers/pos_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
String posCartItemDisplayName(PosCartItem item) {
  if (item.isGift) {
    return '${item.product.name} (${OrdersLabels.giftSuffix})';
  }

  final chipLabel = item.selectedChipLabel?.trim();
  if (chipLabel == null || chipLabel.isEmpty) {
    return item.product.name;
  }

  return '${item.product.name} ($chipLabel)';
}
