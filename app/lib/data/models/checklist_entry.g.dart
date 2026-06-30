// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChecklistEntry _$ChecklistEntryFromJson(Map<String, dynamic> json) =>
    _ChecklistEntry(
      id: (json['id'] as num).toInt(),
      templateId: (json['template_id'] as num).toInt(),
      checklistDate: json['checklist_date'] as String,
      completed: json['completed'] as bool? ?? false,
      completedBy: json['completed_by'] as String? ?? '',
      completedAt: parseApiDateTime(json['completed_at'] as String?),
      createdAt: parseApiDateTime(json['created_at'] as String?),
      templateName: json['template_name'] as String?,
      templatePeriod: json['template_period'] as String?,
      templateSortOrder: (json['template_sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ChecklistEntryToJson(_ChecklistEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'template_id': instance.templateId,
      'checklist_date': instance.checklistDate,
      'completed': instance.completed,
      'completed_by': instance.completedBy,
      'completed_at': instance.completedAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'template_name': instance.templateName,
      'template_period': instance.templatePeriod,
      'template_sort_order': instance.templateSortOrder,
    };
