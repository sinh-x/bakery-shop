// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Order _$OrderFromJson(Map<String, dynamic> json) => _Order(
  id: json['id'] as String,
  orderRef: json['orderRef'] as String,
  customerName: json['customerName'] as String,
  customerPhone: json['customerPhone'] as String? ?? '',
  items: (json['items'] as List<dynamic>)
      .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  totalPrice: (json['totalPrice'] as num).toDouble(),
  status: json['status'] as String? ?? 'new',
  dueDate: json['dueDate'] as String?,
  dueTime: json['dueTime'] as String?,
  deliveryType: json['deliveryType'] as String? ?? 'pickup',
  deliveryAddress: json['deliveryAddress'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
  source: json['source'] as String? ?? '',
  createdBy: json['createdBy'] as String? ?? '',
  amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0.0,
  isPaid: json['isPaid'] as bool? ?? false,
  packingChecklist:
      (json['packingChecklist'] as List<dynamic>?)
          ?.map((e) => PackingItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$OrderToJson(_Order instance) => <String, dynamic>{
  'id': instance.id,
  'orderRef': instance.orderRef,
  'customerName': instance.customerName,
  'customerPhone': instance.customerPhone,
  'items': instance.items,
  'totalPrice': instance.totalPrice,
  'status': instance.status,
  'dueDate': instance.dueDate,
  'dueTime': instance.dueTime,
  'deliveryType': instance.deliveryType,
  'deliveryAddress': instance.deliveryAddress,
  'notes': instance.notes,
  'source': instance.source,
  'createdBy': instance.createdBy,
  'amountPaid': instance.amountPaid,
  'isPaid': instance.isPaid,
  'packingChecklist': instance.packingChecklist,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};
