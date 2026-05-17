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
  productCode: json['product_code'] as String? ?? '',
  priceChips:
      (json['price_chips'] as List<dynamic>?)
          ?.map((e) => PriceChip.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  attributes:
      (json['attributes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  enumAttributes:
      (json['enum_attributes'] as List<dynamic>?)
          ?.map((e) => EnumAttribute.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  stockQty: (json['stock_qty'] as num?)?.toInt(),
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
  'product_code': instance.productCode,
  'price_chips': instance.priceChips,
  'attributes': instance.attributes,
  'enum_attributes': instance.enumAttributes,
  'stock_qty': instance.stockQty,
};
