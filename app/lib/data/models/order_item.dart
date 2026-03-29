import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_item.freezed.dart';
part 'order_item.g.dart';

@freezed
sealed class OrderItem with _$OrderItem {
  const factory OrderItem({
    required String productId,
    required String productName,
    @Default(1) int quantity,
    required double unitPrice,
    @Default('') String notes,
    @Default(false) bool isBirthday,
    int? age,
  }) = _OrderItem;

  factory OrderItem.fromJson(Map<String, dynamic> json) =>
      _$OrderItemFromJson(json);
}
