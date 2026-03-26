// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChecklistTemplate _$ChecklistTemplateFromJson(Map<String, dynamic> json) =>
    _ChecklistTemplate(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      period: json['period'] as String? ?? 'opening',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
    );

Map<String, dynamic> _$ChecklistTemplateToJson(_ChecklistTemplate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'period': instance.period,
      'sort_order': instance.sortOrder,
      'active': instance.active,
      'created_at': instance.createdAt,
    };
