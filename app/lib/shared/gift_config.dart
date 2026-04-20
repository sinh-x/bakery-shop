/// Shared auto-gift configuration for POS and order creation flows.
///
/// When a customer orders tang_kem products totaling >= [giftThreshold],
/// these gift extras are automatically added to the order.
class GiftConfig {
  GiftConfig._();

  /// Minimum total (VND) of tang_kem products to trigger auto-gifts.
  static const double giftThreshold = 100000;

  /// Gift extras: (name, price in VND).
  static const List<(String, double)> giftExtras = [
    ('Nến', 5000),
    ('Đĩa muỗng', 10000),
    ('Nón', 5000),
  ];
}
