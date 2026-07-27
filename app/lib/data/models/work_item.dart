import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_item.freezed.dart';
part 'work_item.g.dart';

/// A blank (phôi bánh) assigned to a work item via the `order_item_blanks`
/// junction table (DG-294). Many blanks may be assigned to a single work
/// item, each with its own `quantity` and `notes`.
///
/// `blankName` is not currently emitted by the backend; the Flutter client
/// resolves it via `blankByIdProvider` when rendering line items. It is kept
/// in the model so display code can rely on a single source of truth.
@freezed
sealed class BlankAssignment with _$BlankAssignment {
  const factory BlankAssignment({
    /// Junction-row id from `order_item_blanks.id` (null until persisted).
    int? id,
    @JsonKey(name: 'blankId') required int blankId,
    @Default('') String blankName,
    @Default(1.0) double quantity,
    @Default('') String notes,
  }) = _BlankAssignment;

  factory BlankAssignment.fromJson(Map<String, dynamic> json) =>
      _$BlankAssignmentFromJson(json);
}

@freezed
sealed class WorkItem with _$WorkItem {
  const factory WorkItem({
    required String id,
    required String orderId,
    @Default('') String productId,
    required String productName,
    @Default(1) int quantity,
    @Default(0.0) double unitPrice,
    double? assignedPrice,
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
    @Default(<BlankAssignment>[]) List<BlankAssignment> blanks,
  }) = _WorkItem;

  factory WorkItem.fromJson(Map<String, dynamic> json) =>
      _$WorkItemFromJson(json);
}