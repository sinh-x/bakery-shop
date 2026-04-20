// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_browse_photo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CatalogBrowsePhoto _$CatalogBrowsePhotoFromJson(Map<String, dynamic> json) =>
    _CatalogBrowsePhoto(
      id: (json['id'] as num).toInt(),
      productId: (json['product_id'] as num).toInt(),
      filePath: json['file_path'] as String,
      caption: json['caption'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String?,
      photoHash: json['photo_hash'] as String?,
      productName: json['productName'] as String,
    );

Map<String, dynamic> _$CatalogBrowsePhotoToJson(_CatalogBrowsePhoto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'product_id': instance.productId,
      'file_path': instance.filePath,
      'caption': instance.caption,
      'tags': instance.tags,
      'position': instance.position,
      'created_at': instance.createdAt,
      'photo_hash': instance.photoHash,
      'productName': instance.productName,
    };
