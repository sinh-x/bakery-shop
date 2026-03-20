// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_transaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PaymentTransaction _$PaymentTransactionFromJson(Map<String, dynamic> json) =>
    _PaymentTransaction(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      type: json['type'] as String? ?? 'deposit',
      method: json['method'] as String? ?? 'cash',
      amount: (json['amount'] as num).toDouble(),
      notes: json['note'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$PaymentTransactionToJson(_PaymentTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'orderId': instance.orderId,
      'type': instance.type,
      'method': instance.method,
      'amount': instance.amount,
      'note': instance.notes,
      'createdAt': instance.createdAt,
    };
