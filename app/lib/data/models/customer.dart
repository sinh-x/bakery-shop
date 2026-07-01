import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

@freezed
sealed class Customer with _$Customer {
  const factory Customer({
    required int id,
    required String name,
    @Default('') String phone,
    @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? updatedAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

/// Response envelope returned by POST /api/customers and PATCH /api/customers/{id}.
///
/// The backend flattens the customer fields and adds `sharedPhoneCustomers`
/// alongside them (FR2a). This record pairs the parsed [Customer] with the
/// list of other customers sharing the same phone number, so the UI can
/// surface phone-sharing visibility on create/edit (AC6, AC8).
typedef CustomerMutationResult =
    ({Customer customer, List<Customer> sharedPhoneCustomers});