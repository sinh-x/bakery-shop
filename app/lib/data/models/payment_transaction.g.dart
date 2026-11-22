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
      createdAt: parseApiDateTime(json['createdAt'] as String?),
      invalidatedAt: parseApiDateTime(json['invalidatedAt'] as String?),
      invalidatedBy: json['invalidatedBy'] as String? ?? '',
      paymentSource: json['paymentSource'] as String?,
      destinationStatus: json['destinationStatus'] as String? ?? 'known',
      destinationResolvedAt: parseApiDateTime(
        json['destinationResolvedAt'] as String?,
      ),
      destinationResolvedBy: json['destinationResolvedBy'] as String? ?? '',
    );

Map<String, dynamic> _$PaymentTransactionToJson(_PaymentTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'orderId': instance.orderId,
      'type': instance.type,
      'method': instance.method,
      'amount': instance.amount,
      'note': instance.notes,
      'createdAt': timestampToJson(instance.createdAt),
      'invalidatedAt': timestampToJson(instance.invalidatedAt),
      'invalidatedBy': instance.invalidatedBy,
      'paymentSource': instance.paymentSource,
      'destinationStatus': instance.destinationStatus,
      'destinationResolvedAt': timestampToJson(instance.destinationResolvedAt),
      'destinationResolvedBy': instance.destinationResolvedBy,
    };
