// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Product _$ProductFromJson(Map<String, dynamic> json) => _Product(
  id: json['id'] as String,
  name: json['name'] as String,
  category: json['category'] as String? ?? 'cake',
  basePrice: (json['basePrice'] as num?)?.toDouble() ?? 0,
  unit: json['unit'] as String? ?? '',
  active: json['active'] as bool? ?? true,
);

Map<String, dynamic> _$ProductToJson(_Product instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'category': instance.category,
  'basePrice': instance.basePrice,
  'unit': instance.unit,
  'active': instance.active,
};
