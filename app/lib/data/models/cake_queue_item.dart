/// Work item enriched with order context — returned by GET /api/work-items.
/// Plain Dart class (no freezed), used only in the cake queue view.
class CakeQueueItem {
  final String id;
  final String orderId;
  final String orderRef;
  final String customerName;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String notes;
  final int position;
  final String status;
  final bool isBirthday;
  final int? age;
  /// Selected candle type carried through the cake queue display model
  /// (DG-340 Phase 1). Sourced from `work_item.attributes['candle_type']`
  /// by the API layer; null when no candle type is set (FR2, AC7). Display
  /// phases render it via [OrdersLabels.candleTypeLabel] alongside the birthday
  /// indicator (FR4).
  final String? candleType;
  final String? dueDate;
  final String? dueTime;
  final String? createdAt;
  final String orderStatus;
  final int blankCount;
  /// Selected enum attributes for this work item (e.g. `nhan_banh`, `candle_type`)
  /// sourced from `order_items.attributes` via the cake queue API response.
  /// Populated as `Map<String, dynamic>` by [fromJson]; empty dict when no
  /// attributes are stored (FR5, AC5). Display phases render it via
  /// `buildEnumAttributeLines()` together with `productsProvider`-resolved
  /// `enumAttributes` (Phase 3/4).
  final Map<String, dynamic> attributes;

  const CakeQueueItem({
    required this.id,
    required this.orderId,
    required this.orderRef,
    required this.customerName,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.notes,
    required this.position,
    required this.status,
    required this.isBirthday,
    this.age,
    this.candleType,
    this.dueDate,
    this.dueTime,
    this.createdAt,
    required this.orderStatus,
    this.blankCount = 0,
    this.attributes = const {},
  });

  factory CakeQueueItem.fromJson(Map<String, dynamic> json) => CakeQueueItem(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        orderRef: json['orderRef'] as String,
        customerName: json['customerName'] as String,
        productId: (json['productId'] as String?) ?? '',
        productName: json['productName'] as String,
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        notes: (json['notes'] as String?) ?? '',
        position: json['position'] as int,
        status: json['status'] as String,
        isBirthday: json['isBirthday'] as bool? ?? false,
        age: json['age'] as int?,
        candleType: json['candleType'] as String?,
        dueDate: json['dueDate'] as String?,
        dueTime: json['dueTime'] as String?,
        createdAt: json['createdAt'] as String?,
        orderStatus: (json['orderStatus'] as String?) ?? '',
        blankCount: (json['blankCount'] as int?) ?? 0,
        attributes: (json['attributes'] as Map<String, dynamic>?) ?? const {},
      );
}
