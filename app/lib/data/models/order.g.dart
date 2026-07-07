// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Order _$OrderFromJson(Map<String, dynamic> json) => _Order(
  id: json['id'] as String,
  orderRef: json['orderRef'] as String,
  publicOrderCode: json['publicOrderCode'] as String? ?? '',
  customerName: json['customerName'] as String,
  customerPhone: json['customerPhone'] as String? ?? '',
  deliveryPhone: json['deliveryPhone'] as String? ?? '',
  customerId: (json['customerId'] as num?)?.toInt(),
  items: (json['items'] as List<dynamic>)
      .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  totalPrice: (json['totalPrice'] as num).toDouble(),
  status: json['status'] as String? ?? 'new',
  dueDate: json['dueDate'] as String?,
  dueTime: json['dueTime'] as String?,
  deliveryType: json['deliveryType'] as String? ?? 'pickup',
  deliveryAddress: json['deliveryAddress'] as String? ?? '',
  shippingFee: (json['shippingFee'] as num?)?.toDouble() ?? 0.0,
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
  workTicketPrintedAt: json['workTicketPrintedAt'] as String?,
  workTicketPrintedBy: json['workTicketPrintedBy'] as String?,
  createdAt: parseApiDateTimeRequired(json['createdAt'] as String),
  updatedAt: parseApiDateTimeRequired(json['updatedAt'] as String),
);

Map<String, dynamic> _$OrderToJson(_Order instance) => <String, dynamic>{
  'id': instance.id,
  'orderRef': instance.orderRef,
  'publicOrderCode': instance.publicOrderCode,
  'customerName': instance.customerName,
  'customerPhone': instance.customerPhone,
  'deliveryPhone': instance.deliveryPhone,
  'customerId': instance.customerId,
  'items': instance.items,
  'totalPrice': instance.totalPrice,
  'status': instance.status,
  'dueDate': instance.dueDate,
  'dueTime': instance.dueTime,
  'deliveryType': instance.deliveryType,
  'deliveryAddress': instance.deliveryAddress,
  'shippingFee': instance.shippingFee,
  'notes': instance.notes,
  'source': instance.source,
  'createdBy': instance.createdBy,
  'amountPaid': instance.amountPaid,
  'isPaid': instance.isPaid,
  'packingChecklist': instance.packingChecklist,
  'workTicketPrintedAt': instance.workTicketPrintedAt,
  'workTicketPrintedBy': instance.workTicketPrintedBy,
  'createdAt': timestampToJson(instance.createdAt),
  'updatedAt': timestampToJson(instance.updatedAt),
};
