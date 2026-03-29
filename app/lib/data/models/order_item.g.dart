// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_OrderItem _$OrderItemFromJson(Map<String, dynamic> json) => _OrderItem(
  productId: json['productId'] as String,
  productName: json['productName'] as String,
  quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  unitPrice: (json['unitPrice'] as num).toDouble(),
  notes: json['notes'] as String? ?? '',
  isBirthday: json['isBirthday'] as bool? ?? false,
  age: (json['age'] as num?)?.toInt(),
);

Map<String, dynamic> _$OrderItemToJson(_OrderItem instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'productName': instance.productName,
      'quantity': instance.quantity,
      'unitPrice': instance.unitPrice,
      'notes': instance.notes,
      'isBirthday': instance.isBirthday,
      'age': instance.age,
    };
