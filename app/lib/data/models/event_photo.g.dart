// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_photo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_EventPhoto _$EventPhotoFromJson(Map<String, dynamic> json) => _EventPhoto(
  id: (json['id'] as num).toInt(),
  eventId: (json['event_id'] as num).toInt(),
  photoId: (json['photo_id'] as num).toInt(),
  photoHash: json['photo_hash'] as String,
  tags: json['tags'] as String? ?? '',
  position: (json['position'] as num?)?.toInt() ?? 0,
  createdAt: json['created_at'] as String?,
);

Map<String, dynamic> _$EventPhotoToJson(_EventPhoto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'event_id': instance.eventId,
      'photo_id': instance.photoId,
      'photo_hash': instance.photoHash,
      'tags': instance.tags,
      'position': instance.position,
      'created_at': instance.createdAt,
    };
