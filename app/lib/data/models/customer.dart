import 'package:freezed_annotation/freezed_annotation.dart';

import '../../shared/utils/date_formatting.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

@freezed
sealed class CustomerPhone with _$CustomerPhone {
  const factory CustomerPhone({
    required String phone,
    @JsonKey(name: 'isPrimary') @Default(false) bool isPrimary,
  }) = _CustomerPhone;

  factory CustomerPhone.fromJson(Map<String, dynamic> json) =>
      _$CustomerPhoneFromJson(json);
}

/// Per-customer per-year order summary (DG-206 FR7).
///
/// Returned by `GET /api/customers/:id` as the `yearSummary` field. Contains
/// the current year's order count and total volume for display in customer
/// cards across order screens.
@freezed
sealed class CustomerYearSummary with _$CustomerYearSummary {
  const factory CustomerYearSummary({
    required int year,
    @JsonKey(name: 'orderCount') @Default(0) int orderCount,
    @JsonKey(name: 'totalVolume') @Default(0.0) double totalVolume,
  }) = _CustomerYearSummary;

  factory CustomerYearSummary.fromJson(Map<String, dynamic> json) =>
      _$CustomerYearSummaryFromJson(json);
}

@freezed
sealed class Customer with _$Customer {
  const factory Customer({
    required int id,
    required String name,
    @Default('') String phone,
    @Default(<CustomerPhone>[]) List<CustomerPhone> phones,
    @JsonKey(name: 'createdAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? createdAt,
    @JsonKey(name: 'updatedAt', fromJson: parseApiDateTime, toJson: timestampToJson)
    DateTime? updatedAt,
    /// Per-year order summary from backend `customer_year_summary` table
    /// (DG-206 Phase 1). Only populated by `GET /api/customers/:id`; list
    /// responses do not include it.
    @JsonKey(name: 'yearSummary') CustomerYearSummary? yearSummary,
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