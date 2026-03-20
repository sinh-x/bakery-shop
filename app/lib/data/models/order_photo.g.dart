// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_photo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_OrderPhoto _$OrderPhotoFromJson(Map<String, dynamic> json) => _OrderPhoto(
  id: (json['id'] as num).toInt(),
  orderId: (json['order_id'] as num).toInt(),
  photoHash: json['photo_hash'] as String,
  tags: json['tags'] as String? ?? '',
  position: (json['position'] as num?)?.toInt() ?? 0,
  createdAt: json['created_at'] as String?,
);

Map<String, dynamic> _$OrderPhotoToJson(_OrderPhoto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'order_id': instance.orderId,
      'photo_hash': instance.photoHash,
      'tags': instance.tags,
      'position': instance.position,
      'created_at': instance.createdAt,
    };
