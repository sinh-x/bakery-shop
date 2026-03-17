// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Product _$ProductFromJson(Map<String, dynamic> json) => _Product(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  category: json['category'] as String? ?? 'bread',
  basePrice: (json['base_price'] as num?)?.toDouble() ?? 0,
  cost: (json['cost'] as num?)?.toDouble() ?? 0,
  recipeNotes: json['recipe_notes'] as String? ?? '',
  active: (json['active'] as num?)?.toInt() ?? 1,
  photoPath: json['photo_path'] as String? ?? '',
);

Map<String, dynamic> _$ProductToJson(_Product instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'category': instance.category,
  'base_price': instance.basePrice,
  'cost': instance.cost,
  'recipe_notes': instance.recipeNotes,
  'active': instance.active,
  'photo_path': instance.photoPath,
};
