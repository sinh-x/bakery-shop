import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_item.freezed.dart';
part 'work_item.g.dart';

@freezed
sealed class WorkItem with _$WorkItem {
  const factory WorkItem({
    required String id,
    required String orderId,
    @Default('') String productId,
    required String productName,
    @Default(1) int quantity,
    @Default(0.0) double unitPrice,
    @Default('') String notes,
    @Default('pending') String status,
    String? dueDate,
    String? dueTime,
    String? deliveryType,
    String? deliveryAddress,
    @Default(0) int position,
    @Default(false) bool isBirthday,
    @Default(false) bool isExtra,
    @Default(false) bool isGift,
    int? age,
    String? createdAt,
    String? updatedAt,
    @Default({}) Map<String, dynamic> attributes,
  }) = _WorkItem;

  factory WorkItem.fromJson(Map<String, dynamic> json) =>
      _$WorkItemFromJson(json);
}
