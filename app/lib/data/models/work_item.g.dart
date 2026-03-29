// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorkItem _$WorkItemFromJson(Map<String, dynamic> json) => _WorkItem(
  id: json['id'] as String,
  orderId: json['orderId'] as String,
  productId: json['productId'] as String? ?? '',
  productName: json['productName'] as String,
  quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
  notes: json['notes'] as String? ?? '',
  status: json['status'] as String? ?? 'pending',
  dueDate: json['dueDate'] as String?,
  dueTime: json['dueTime'] as String?,
  deliveryType: json['deliveryType'] as String?,
  deliveryAddress: json['deliveryAddress'] as String?,
  position: (json['position'] as num?)?.toInt() ?? 0,
  isBirthday: json['isBirthday'] as bool? ?? false,
  isExtra: json['isExtra'] as bool? ?? false,
  isGift: json['isGift'] as bool? ?? false,
  age: (json['age'] as num?)?.toInt(),
  createdAt: json['createdAt'] as String?,
  updatedAt: json['updatedAt'] as String?,
);

Map<String, dynamic> _$WorkItemToJson(_WorkItem instance) => <String, dynamic>{
  'id': instance.id,
  'orderId': instance.orderId,
  'productId': instance.productId,
  'productName': instance.productName,
  'quantity': instance.quantity,
  'unitPrice': instance.unitPrice,
  'notes': instance.notes,
  'status': instance.status,
  'dueDate': instance.dueDate,
  'dueTime': instance.dueTime,
  'deliveryType': instance.deliveryType,
  'deliveryAddress': instance.deliveryAddress,
  'position': instance.position,
  'isBirthday': instance.isBirthday,
  'isExtra': instance.isExtra,
  'isGift': instance.isGift,
  'age': instance.age,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};
