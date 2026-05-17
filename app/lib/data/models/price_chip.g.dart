// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_chip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PriceChip _$PriceChipFromJson(Map<String, dynamic> json) => _PriceChip(
  id: (json['id'] as num).toInt(),
  label: json['label'] as String,
  price: (json['price'] as num).toDouble(),
  position: (json['position'] as num?)?.toInt() ?? 0,
  stockQty: (json['stock_qty'] as num?)?.toInt(),
);

Map<String, dynamic> _$PriceChipToJson(_PriceChip instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'price': instance.price,
      'position': instance.position,
      'stock_qty': instance.stockQty,
    };
