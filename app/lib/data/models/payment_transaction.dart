import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

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
    @JsonKey(
      name: 'createdAt',
      fromJson: parseApiDateTime,
      toJson: timestampToJson,
    )
    DateTime? createdAt,
    @JsonKey(
      name: 'invalidatedAt',
      fromJson: parseApiDateTime,
      toJson: timestampToJson,
    )
    DateTime? invalidatedAt,
    @JsonKey(name: 'invalidatedBy') @Default('') String invalidatedBy,
    @JsonKey(name: 'paymentSource') String? paymentSource,
    @Default('known') String destinationStatus,
    @JsonKey(fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? destinationResolvedAt,
    @Default('') String destinationResolvedBy,
  }) = _PaymentTransaction;

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      _$PaymentTransactionFromJson(json);
}

extension PaymentDestinationState on PaymentTransaction {
  bool get hasUnknownOrigin =>
      method == 'unknown' || destinationResolvedAt != null;
}
