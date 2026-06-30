// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'knowledge_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_KnowledgeEntry _$KnowledgeEntryFromJson(Map<String, dynamic> json) =>
    _KnowledgeEntry(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'note',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
      loggedBy: json['logged_by'] as String? ?? '',
      source: json['source'] as String? ?? 'app',
      createdAt: parseApiDateTimeRequired(json['created_at'] as String),
      updatedAt: parseApiDateTimeRequired(json['updated_at'] as String),
      pinned: json['pinned'] as bool? ?? false,
      pinnedAt: parseApiDateTime(json['pinned_at'] as String?),
      photos:
          (json['photos'] as List<dynamic>?)
              ?.map((e) => KnowledgePhoto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KnowledgePhoto>[],
    );

Map<String, dynamic> _$KnowledgeEntryToJson(_KnowledgeEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'content': instance.content,
      'type': instance.type,
      'tags': instance.tags,
      'logged_by': instance.loggedBy,
      'source': instance.source,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'pinned': instance.pinned,
      'pinned_at': instance.pinnedAt?.toIso8601String(),
      'photos': instance.photos,
    };

_KnowledgePhoto _$KnowledgePhotoFromJson(Map<String, dynamic> json) =>
    _KnowledgePhoto(
      hash: json['hash'] as String,
      url: json['url'] as String,
      caption: json['caption'] as String? ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$KnowledgePhotoToJson(_KnowledgePhoto instance) =>
    <String, dynamic>{
      'hash': instance.hash,
      'url': instance.url,
      'caption': instance.caption,
      'position': instance.position,
    };
