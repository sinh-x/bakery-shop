import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_balance.freezed.dart';
part 'account_balance.g.dart';

@freezed
sealed class AccountBalance with _$AccountBalance {
  const factory AccountBalance({
    @JsonKey(name: 'accountId') required String accountId,
    required String code,
    required String name,
    required String type,
    @JsonKey(name: 'parentId') String? parentId,
    @Default(0.0) double debit,
    @Default(0.0) double credit,
    @Default(0.0) double balance,
  }) = _AccountBalance;

  factory AccountBalance.fromJson(Map<String, dynamic> json) =>
      _$AccountBalanceFromJson(json);
}