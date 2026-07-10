import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';
import 'order_item.dart';
import 'packing_item.dart';

part 'order.freezed.dart';
part 'order.g.dart';

@freezed
sealed class Order with _$Order {
  const factory Order({
    required String id,
    required String orderRef,
    @Default('') String publicOrderCode,
    required String customerName,
    @Default('') String customerPhone,
    @Default('') String deliveryPhone,
    int? customerId,
    required List<OrderItem> items,
    required double totalPrice,
    @Default('new') String status,
    String? dueDate,
    String? dueTime,
    @Default('pickup') String deliveryType,
    @Default('') String deliveryAddress,
    @Default(0.0) double shippingFee,
    @Default('') String notes,
    @Default('') String source,
    @Default('') String createdBy,
    @Default(0.0) double amountPaid,
    @Default(false) bool isPaid,
    @Default([]) List<PackingItem> packingChecklist,
    String? workTicketPrintedAt,
    String? workTicketPrintedBy,
    @JsonKey(name: 'createdAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)
    required DateTime createdAt,
    @JsonKey(name: 'updatedAt', fromJson: parseApiDateTimeRequired, toJson: timestampToJson)
    required DateTime updatedAt,
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
}
