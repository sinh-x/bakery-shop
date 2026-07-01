// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Customer _$CustomerFromJson(Map<String, dynamic> json) => _Customer(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  phone: json['phone'] as String? ?? '',
  createdAt: parseApiDateTime(json['createdAt'] as String?),
  updatedAt: parseApiDateTime(json['updatedAt'] as String?),
);

Map<String, dynamic> _$CustomerToJson(_Customer instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'phone': instance.phone,
  'createdAt': timestampToJson(instance.createdAt),
  'updatedAt': timestampToJson(instance.updatedAt),
};
