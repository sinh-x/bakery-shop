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
  final String? dueDate;
  final String? dueTime;
  final String? createdAt;

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
    this.dueDate,
    this.dueTime,
    this.createdAt,
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
        dueDate: json['dueDate'] as String?,
        dueTime: json['dueTime'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}
