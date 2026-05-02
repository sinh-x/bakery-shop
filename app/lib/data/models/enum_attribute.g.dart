// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enum_attribute.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_EnumOption _$EnumOptionFromJson(Map<String, dynamic> json) => _EnumOption(
  id: (json['id'] as num).toInt(),
  valueVi: json['value_vi'] as String,
  sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  active: (json['active'] as num?)?.toInt() ?? 1,
  isDefault: json['is_default'] as bool? ?? false,
);

Map<String, dynamic> _$EnumOptionToJson(_EnumOption instance) =>
    <String, dynamic>{
      'id': instance.id,
      'value_vi': instance.valueVi,
      'sort_order': instance.sortOrder,
      'active': instance.active,
      'is_default': instance.isDefault,
    };

_EnumAttribute _$EnumAttributeFromJson(Map<String, dynamic> json) =>
    _EnumAttribute(
      attributeType: json['attribute_type'] as String,
      labelVi: json['label_vi'] as String,
      defaultOptionId: (json['default_option_id'] as num?)?.toInt(),
      options:
          (json['options'] as List<dynamic>?)
              ?.map((e) => EnumOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$EnumAttributeToJson(_EnumAttribute instance) =>
    <String, dynamic>{
      'attribute_type': instance.attributeType,
      'label_vi': instance.labelVi,
      'default_option_id': instance.defaultOptionId,
      'options': instance.options,
    };
