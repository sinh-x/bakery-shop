import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'payment_transaction.freezed.dart';
part 'payment_transaction.g.dart';

DateTime? _parseNullableDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return parseApiDateTime(value);
}

@freezed
sealed class PaymentTransaction with _$PaymentTransaction {
  const factory PaymentTransaction({
    required String id,
    required String orderId,
    @Default('deposit') String type,
    @Default('cash') String method,
    required double amount,
    @JsonKey(name: 'note') @Default('') String notes,
    @JsonKey(fromJson: _parseNullableDateTime) DateTime? createdAt,
    @JsonKey(fromJson: _parseNullableDateTime) DateTime? invalidatedAt,
    @Default('') String invalidatedBy,
  }) = _PaymentTransaction;

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      _$PaymentTransactionFromJson(json);
}
