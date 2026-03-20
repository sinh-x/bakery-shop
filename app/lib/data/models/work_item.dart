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
    String? createdAt,
    String? updatedAt,
  }) = _WorkItem;

  factory WorkItem.fromJson(Map<String, dynamic> json) =>
      _$WorkItemFromJson(json);
}
