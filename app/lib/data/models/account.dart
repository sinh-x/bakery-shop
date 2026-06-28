import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';
part 'account.g.dart';

@freezed
sealed class Account with _$Account {
  const factory Account({
    required String id,
    required String code,
    required String name,
    required String type,
    @JsonKey(name: 'parentId') String? parentId,
    @JsonKey(name: 'isActive') @Default(true) bool isActive,
    @JsonKey(name: 'createdAt') String? createdAt,
    @Default(<Account>[]) List<Account> children,
  }) = _Account;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);
}