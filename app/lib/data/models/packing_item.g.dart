// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'packing_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PackingItem _$PackingItemFromJson(Map<String, dynamic> json) => _PackingItem(
  name: json['name'] as String,
  isChecked: json['isChecked'] as bool? ?? false,
);

Map<String, dynamic> _$PackingItemToJson(_PackingItem instance) =>
    <String, dynamic>{'name': instance.name, 'isChecked': instance.isChecked};
