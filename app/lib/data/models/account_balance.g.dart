// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_balance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AccountBalance _$AccountBalanceFromJson(Map<String, dynamic> json) =>
    _AccountBalance(
      accountId: json['accountId'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      parentId: json['parentId'] as String?,
      debit: (json['debit'] as num?)?.toDouble() ?? 0.0,
      credit: (json['credit'] as num?)?.toDouble() ?? 0.0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$AccountBalanceToJson(_AccountBalance instance) =>
    <String, dynamic>{
      'accountId': instance.accountId,
      'code': instance.code,
      'name': instance.name,
      'type': instance.type,
      'parentId': instance.parentId,
      'debit': instance.debit,
      'credit': instance.credit,
      'balance': instance.balance,
    };
