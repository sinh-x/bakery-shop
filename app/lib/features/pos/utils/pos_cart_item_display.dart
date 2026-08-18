import '../../../providers/pos_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

String posCartItemDisplayName(PosCartItem item) {
  if (item.isGift) {
    return '${item.product.name} (${VN.giftSuffix})';
  }

  final chipLabel = item.selectedChipLabel?.trim();
  if (chipLabel == null || chipLabel.isEmpty) {
    return item.product.name;
  }

  return '${item.product.name} ($chipLabel)';
}
