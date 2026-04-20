// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_tag.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CatalogTagDef _$CatalogTagDefFromJson(Map<String, dynamic> json) =>
    _CatalogTagDef(
      category: json['category'] as String,
      key: json['key'] as String,
      label: json['label'] as String,
      color: (json['color'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CatalogTagDefToJson(_CatalogTagDef instance) =>
    <String, dynamic>{
      'category': instance.category,
      'key': instance.key,
      'label': instance.label,
      'color': instance.color,
    };
