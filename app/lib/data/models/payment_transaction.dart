import 'package:freezed_annotation/freezed_annotation.dart';

part 'payment_transaction.freezed.dart';
part 'payment_transaction.g.dart';

@freezed
sealed class PaymentTransaction with _$PaymentTransaction {
  const factory PaymentTransaction({
    required String id,
    required String orderId,
    @Default('deposit') String type,
    @Default('cash') String method,
    required double amount,
    @JsonKey(name: 'note') @Default('') String notes,
    String? createdAt,
    String? invalidatedAt,
    @Default('') String invalidatedBy,
  }) = _PaymentTransaction;

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      _$PaymentTransactionFromJson(json);
}
