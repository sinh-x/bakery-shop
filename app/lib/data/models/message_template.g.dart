// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MessageTemplate _$MessageTemplateFromJson(Map<String, dynamic> json) =>
    _MessageTemplate(
      id: (json['id'] as num).toInt(),
      scenario: json['scenario'] as String,
      name: json['name'] as String,
      body: json['body'] as String? ?? '',
      isSystem: json['is_system'] as bool? ?? false,
      createdByStaffId: (json['created_by_staff_id'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: parseApiDateTime(json['created_at'] as String?),
      updatedAt: parseApiDateTime(json['updated_at'] as String?),
    );

Map<String, dynamic> _$MessageTemplateToJson(_MessageTemplate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'scenario': instance.scenario,
      'name': instance.name,
      'body': instance.body,
      'is_system': instance.isSystem,
      'created_by_staff_id': instance.createdByStaffId,
      'sort_order': instance.sortOrder,
      'active': instance.active,
      'created_at': timestampToJson(instance.createdAt),
      'updated_at': timestampToJson(instance.updatedAt),
    };
